// MCP 工具动态注册域（先例 = ToolMount 自注册域件 / HttpTemplate.syncTemplateTools 动态域）：
// 把 mcp_servers 表的工具缓存落进 toolRegistry——只管「注册面」一层；启用面（assistants.
// mcpServers 装载 + AssistantToolsPage 绑定卡）与声明面（ChatContextUsage.collectTools 追加段）
// 在各自件，执行面（executeToolCall 轮次机）与 role:tool 回执面全走既有管路零改动。
// · 条目形态：name = 'mcp__<服务器名>__<工具名>' 三段名（mcpToolNameOf 单源）、
//   modeDriven: true（不走 assistants.tools 启用清单——启用面按助手勾选服务器，绑定消费在
//   collectTools 追加段按 registeredMcpEntriesFor 求交）、defaultEnabled: false、
//   group: TOOL_GROUP_MCP（**不进 ToolTypes.TOOL_GROUP_ORDER**——modeDriven 组不参与组卡
//   系统，双路不出页，tpl_* 模板工具同款惯例；group 必填字段的编译期防漏标照旧生效）。
// · 控制台三层闸已随控制台助手整体退役（fail-closed 判据失去对象）；启用面现为
//   「服务器勾选 ∩ 服务器 enabled」单层，不进工具页组卡系统的形态不变（沿革 = 变更记录）。
// · 注册/注销成对（防注册表无界增长，宪法内存防线）：注销 = 注册表中 isMcpToolName 且库
//   现值已无对应的全量 unregister（服务器删除/停用/工具消失三态同口）；注册 = 同名覆盖
//   刷新 desc/schema。
// · 兜底校验两道（编辑页保存闸与 McpDb 增改闸之外的第三道）：服务器名非法 → 跳过注册 +
//   lastError 回写中文摘要；工具名越 OpenAI 兼容口 ^[A-Za-z0-9_-]{1,64}$（Gemini 首字符
//   要求由 mcp__ 前缀天然满足）会 400 拒整轮 tools 声明 → 逐件跳过 + 回写摘要，均不炸不闪退。
// · 同步代次：每次 sync 取号、读库 await 后只认最新一代——旧快照晚到不得重注册已删/停用
//   条目；注册/注销/index 替换收在同一同步段内，lastError 回写放其后再 await（新一轮已
//   发起则旧摘要作废）。
// · 库读失败零动作保旧态（不把瞬时 IO 故障放大成能力消失）。
// · serverId → 工具名 index（与注册表同一函数内成对重建，条目数有界）：条目 name 含服务器名
//   不含 serverId，按 serverIds 求交需该映射；极窄并发窗口内 index 与注册表可能错拍 → get
//   返回 undefined 即跳过（防御不炸），下一次 sync 收敛。
// · executor 直持 serverId/服务器名/工具名/url/headersJson/protocolVersion（**执行与闸判定
//   不靠名字反解**；protocolVersion 漏传则对 tools/call 链路静默回自动档）；配置变更经保存
//   链 clearMcpSession + 重注册换新 executor，在途执行持旧值属既有竞态口径。
// · 依赖方向：引 ToolContracts/ToolRegistry（叶子）、ChatDb 委托、McpClient、McpText——
//   ChatContextUsage 引本件 = chat → providers 既有方向，无环。
import { ToolEntry, ToolExecutor } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { toolRegistry } from './ToolRegistry';
import { queryMcpServers, setMcpServerTools } from '../store/ChatDb';
import { McpServerRow } from '../store/McpDb';
import { inlineRefExpansion, isMcpToolName, isValidMcpProviderToolName,
  isValidMcpServerName, mcpToolNameOf, McpToolCacheItem, parseMcpToolCache,
  truncateToolResult } from '../McpText';
import { callMcpTool, McpServerEndpoint } from './McpClient';

// MCP 域组标签（条目 group 字段值域；不进工具页组卡系统，见头注释）
export const TOOL_GROUP_MCP: string = 'MCP 工具';

// 空 object schema 兜底（缓存 inputSchema 空串/坏 JSON/非对象时防 provider 校验空参缺
// type；inlineRefExpansion 在此再跑一次是防御纵深——旧缓存/绕过 UI 落库的数据同守）
const MCP_EMPTY_OBJECT_SCHEMA: string = '{"type":"object","properties":{}}';

// serverId → 该服务器当前注册条目名数组（syncMcpTools 末尾整体替换，见头注释错拍口径）
let mcpServerToolsIndex: Map<string, string[]> = new Map<string, string[]>();

// 同步代次（口径见头注释）：取号后只跨 queryMcpServers 一处 await 校验；循环体不 await。
let mcpSyncGeneration: number = 0;

// lastError 回写载荷（同步段内收集、注册面落定后统一回写——见 syncMcpTools）
interface McpLastErrorWrite {
  id: string;
  toolsJson: string;
  lastSyncAt: number;
  message: string;
}

// 工具执行器：tools/call 经 McpClient（会话自愈一次在其内）→ content 文本化 → >32K 截断
// 留 4K 预览（模型可感知被截）。异常/超时上抛由 ToolRuntime.executeToolCall 包装
// '{"error": ...}'（既有拍板——回执形态零新设计，模型可感知自纠）；argsJson 原串透传
//（非法 JSON 在 McpRpc 内抛中文错同走包装）。无 preflight（审批门二期；ToolLimits 轮数
// 上限既有兜底）
class McpToolExecutor implements ToolExecutor {
  private readonly endpoint: McpServerEndpoint;
  private readonly toolName: string;

  constructor(serverId: string, url: string, headersJson: string, protocolVersion: string,
    toolName: string) {
    this.endpoint = { serverId: serverId, url: url, headersJson: headersJson,
      protocolVersion: protocolVersion };
    this.toolName = toolName;
  }

  async execute(argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    const text: string = await callMcpTool(this.endpoint, this.toolName, argsJson);
    return truncateToolResult(text);
  }
}

// 缓存项 → 注册条目（desc 空回退最小英文句——模型面 desc 惯例英文主体；schema 走展开
// 兜底单点）
function mcpEntryOf(row: McpServerRow, cache: McpToolCacheItem): ToolEntry {
  return {
    name: mcpToolNameOf(row.name, cache.name),
    title: cache.name,
    desc: cache.description !== '' ? cache.description :
      'MCP tool "' + cache.name + '" from server "' + row.name + '".',
    group: TOOL_GROUP_MCP,
    parametersJson: mcpSchemaForRegistration(cache.inputSchema),
    defaultEnabled: false,
    modeDriven: true,
    executor: new McpToolExecutor(row.id, row.url, row.headersJson, row.protocolVersion,
      cache.name)
  };
}

function mcpSchemaForRegistration(inputSchema: string): string {
  const expanded: string = inlineRefExpansion(inputSchema);
  try {
    const raw: object = JSON.parse(expanded);
    if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
      return expanded;
    }
  } catch (e) {
  }
  return MCP_EMPTY_OBJECT_SCHEMA;
}

// 注册面同步（幂等；调用点 = EntryAbility 启动兜底 / 缓存回写后 / 删除级联后）。不发网络：
// 纯 DB 缓存 → 注册表（冷启动不连接也可声明；调用时不可达由 executor 抛错走 error 回执，
// 模型可感知失败并自纠）
export async function syncMcpTools(): Promise<void> {
  const generation: number = ++mcpSyncGeneration;
  let rows: McpServerRow[] = [];
  try {
    rows = await queryMcpServers();
  } catch (e) {
    return; // 库读失败零动作保旧态（上次已知注册面继续可用）
  }
  if (generation !== mcpSyncGeneration) {
    return; // 读库期间已有更新的一次 sync 发起：旧快照作废（防旧值重注册已删/停用条目）
  }
  // 库现值全集（enabled ∧ 缓存非空 ∧ 名字合法的服务器工具）+ 逐服务器注册
  const present: string[] = [];
  const nextIndex: Map<string, string[]> = new Map<string, string[]>();
  // 回写载荷同步段内只收集、注册面落定后统一回写（理由见代次口径）
  const errorWrites: McpLastErrorWrite[] = [];
  for (const row of rows) {
    if (!row.enabled) {
      continue; // 停用 = 注销注册表条目 + 不注入任何对话（mcp_servers.enabled 列义）
    }
    if (!isValidMcpServerName(row.name)) {
      // 同步兜底校验（第三道闸）：跳过注册 + lastError 回写中文摘要（P0-1 不静默——管理页
      // 行卡失败态可见），回写失败不炸不阻断其余服务器
      errorWrites.push({
        id: row.id, toolsJson: row.toolsJson, lastSyncAt: row.lastSyncAt,
        message: '服务器名只能用字母和数字，已跳过注册它的工具'
      });
      continue;
    }
    const caches: McpToolCacheItem[] = parseMcpToolCache(row.toolsJson);
    if (caches.length === 0) {
      continue; // 无缓存（未同步过）= 无可注册件
    }
    const names: string[] = [];
    let skippedCount: number = 0;
    for (const cache of caches) {
      // 单工具启停（二期 D 第三级闸）：停用 = 不注册（声明面/执行面同口收敛——未注册即不
      // 进声明、不可执行）；不计入 skippedCount（用户意图非异常）
      if (!cache.enabled) {
        continue;
      }
      const registeredName: string = mcpToolNameOf(row.name, cache.name);
      // provider 命名约束：单件非法名会 400 整轮 tools 声明请求，跳过该件并回写服务器
      // lastError（P0-1 不静默）
      if (!isValidMcpProviderToolName(registeredName)) {
        skippedCount++;
        continue;
      }
      toolRegistry.register(mcpEntryOf(row, cache));
      names.push(registeredName);
      present.push(registeredName);
    }
    if (skippedCount > 0) {
      errorWrites.push({
        id: row.id, toolsJson: row.toolsJson, lastSyncAt: row.lastSyncAt,
        message: '有 ' + skippedCount + ' 件工具名不符合模型接口的命名规则，已跳过注册'
      });
    }
    nextIndex.set(row.id, names);
  }
  // 注销：注册表中 MCP 域且库现值已无对应的条目（服务器删除/停用/工具消失三态同口；
  // 置于注册后 = 全集已定，注销与注册同函数内成对）
  const stale: string[] = [];
  toolRegistry.all().forEach((entry: ToolEntry): void => {
    if (isMcpToolName(entry.name) && !present.includes(entry.name)) {
      stale.push(entry.name);
    }
  });
  for (const name of stale) {
    toolRegistry.unregister(name);
  }
  mcpServerToolsIndex.clear();
  mcpServerToolsIndex = nextIndex;
  // lastError 回写（注册面已落定；回写失败不炸不阻断——新一轮 sync 已发起则旧摘要作废）
  for (const write of errorWrites) {
    if (generation !== mcpSyncGeneration) {
      break;
    }
    try {
      await setMcpServerTools(write.id, write.toolsJson, write.lastSyncAt, write.message);
    } catch (e) {
    }
  }
}

// 声明追加点用：按助手绑定 serverIds 过滤注册表现值（**同步读、零 IO**——collectTools
// 热路径约束，本函数只读不补）。闸 = 助手勾选 ∩ 服务器 enabled（注册面隐含——停用已注销）
// ∩ 单工具 enabled（注册循环按 cache.enabled 过滤，读注册表即真值）；index 未命中 = 零件
export function registeredMcpEntriesFor(serverIds: string[]): ToolEntry[] {
  const out: ToolEntry[] = [];
  for (const serverId of serverIds) {
    const names: string[] | undefined = mcpServerToolsIndex.get(serverId);
    if (names === undefined) {
      continue;
    }
    for (const name of names) {
      const entry: ToolEntry | undefined = toolRegistry.get(name);
      if (entry !== undefined) {
        out.push(entry);
      }
    }
  }
  return out;
}
