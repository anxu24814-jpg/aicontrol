// 工具调用轮数上限值域（2026-09-09 上限可设置笔；零依赖叶子模块）：全局偏好键
// prefToolStepLimit（键与注释单一来源 AppPreferences.ets）的存储值语义 + 「存储值 → 生效
// 上限」唯一换算点 + UI 滑轨用的存储值域归一。
// ★ 载体沿革（2026-09-27 工具运行参数全局化笔，决明拍板「只在设置页全局控制」）：原载体 =
// assistants.toolStepLimit 列（DB v22，按助手存）——该列同笔退役为**墓碑列**（库内保留、
// 代码面零读写，见 ChatDbSchema 同列注释）；本模块的值域与换算语义逐字未变，只换存储载体。
// 值域（存储值）：0 = 不限制 / 1~TOOL_STEP_LIMIT_MAX(32) = 单次发送内工具调用轮数
// 上限；默认 TOOL_STEP_LIMIT_DEFAULT(32) = 旧全局常量 MAX_TOOL_STEPS 同值，未配置与
// 存量行为逐字节零回归。
// ★ 0 不是真无限（决明 2026-09-09 拍板「0 = 不限 + 内置硬顶 256」）：模型工具死循环会无限
// 续轮扣费，故 0 档由 TOOL_STEP_HARD_CAP(256，对齐 CubeAgent/RikkaHub 公开值) 兜底；到顶
// 仍走 A2 让位轮 + 触顶 notice（ChatStreamFlowCtrl.onStreamDone，2026-09-27 拆分笔随形），与显式设值路径同形。
// ★ 为何独立成文件而不并入 ToolTypes：存储层 AssistantDb 需引用默认值，而 ToolTypes 经
// ToolFunctional → ProviderDb 反向依赖 AssistantDb（链上再引即循环依赖，本项目明令禁）；
// 叶子模块零 import，设置页/发送链/UI 三方共用同一份常量与换算，禁各处自写一套。
export const TOOL_STEP_LIMIT_DEFAULT: number = 32;
export const TOOL_STEP_LIMIT_MAX: number = 32;
export const TOOL_STEP_HARD_CAP: number = 256;

// ── 工具输入预算（★ 2026-09-28 架构收口笔2 R4 档③④；三值 2026-09-27 决明按任务书提案值
// 拍板采纳）──判定落点 = ChatToolRoundCtrl 调用集合入口（判据对象 = 聚合完毕的 argsJson，
// 聚合器与解析器不动）；超限 = 该调用不执行、以 error JSON 回传（卡面 error 态 + 模型可见，
// 保持 tool_calls ↔ tool 结果配对完整），禁静默截断后执行。与 TOOL_STEP_* 的「轮数」是
// 两个维度，勿混。文案数字取常量现读（roundLimit 同款防漂移口径）
// 单次调用参数上限：与 ToolHttp.HTTP_ARGS_MAX_CHARS 同值同口径（工具 HTTP 层同判据的编排
// 层前置——各留各的常量，禁写「两常量相等」类判据）
export const TOOL_ARGS_MAX_CHARS: number = 100000;
// 单轮合计参数上限：4 × 单调用上限（给多调用留半额余量；按调用序累计，超限位起不执行）
export const TOOL_ARGS_ROUND_MAX_CHARS: number = 400000;
// 单轮工具调用数上限：实测常见 1~5，与知识/技能「启用 ≤10」同量级；序位判（第 9 个起不执行）
export const TOOL_CALLS_PER_ROUND_MAX: number = 8;

// ── 工具图挂载数量（★ 2026-10-03 工作区图片读取笔）──判定落点 = ChatToolMediaCtrl
// collectImage / collectToolImage（组件层计数——2026-10-06 代码工作台笔D 拆域随迁）；
// 超限 = collectImage 回 false，执行器中文回执说明。
// 单发送（含全部工具续轮）内执行器经回调最多挂载的图片张数：每张经附件链缩边规格
//（IMAGE_MAX_EDGE_PX=2048/JPEG q85）约数百 token~千级 token，8 张与本文件
// TOOL_CALLS_PER_ROUND_MAX 同量级，防模型自主连环读图把单次发送 token 打爆（rikkahub
// 无上限随历史重发的成本失控实证 = .zcode/workspace-research/report-image-tool-rikkel-20261003.md）。
// ★ 2026-10-06 代码工作台笔D：图片与 PDF 原件（段二直传）共用同一预算——PDF 体积更大
//（≤ DOC_NATIVE_MAX_BYTES 8MB 源件），共用闸保证单发送附件总量有界
export const TOOL_IMAGE_ATTACH_MAX: number = 8;

// ── 会话附件按名匹配查询窗口（★ 2026-10-04 单源笔）──workspace_import 与 http 上传源
// 匹配两域各自 queryAttachmentsByConversation(conversationId, 本值, 0) 的共享窗口；单会话
// 附件超过本值时更早的附件不在匹配域（已知边界，触发概率低）。两消费方 = ToolWorkspace.
// WorkspaceImportExecutor / HttpFlow.executeFlow 上传源匹配段——调窗只改这里，禁两处各写
// 字面量（2026-10-04 前两处散写 500 同值，漂移风险即本常量的立项理由）
export const ATTACHMENT_MATCH_WINDOW_MAX: number = 500;

// 存储值 → 生效上限（发送链与 UI 展示共用的唯一换算点）：0 及负值（脏数据）= 硬顶；
// 1~MAX = 原值；超 MAX（脏数据）= MAX 收口。
// ★ 2026-09-27 自检轮补两处脏值hole（原实现只判 stored <= 0）：①非有限数（NaN）——原式
// 落到 Math.min(NaN, 32) = NaN，闸门 hasBudget 的 `toolStep < NaN` 恒 false ⇒ 工具整轮静默
// 不执行、触顶 notice 报「NaN 轮上限」；②(0, 0.5) 的脏小数——原式取整后得 0，与①同病。
// 两处均收口硬顶（与 0/负值同口径，见下方 clamp 的「不可复用」条；脏值只在手改备份场景
// 可达，正常路径写入的都是 0~32 整数）
export function resolveToolStepLimit(stored: number): number {
  if (!Number.isFinite(stored) || stored <= 0) {
    return TOOL_STEP_HARD_CAP;
  }
  const rounded: number = Math.round(stored);
  return rounded <= 0 ? TOOL_STEP_HARD_CAP : Math.min(rounded, TOOL_STEP_LIMIT_MAX);
}

// 存储值域归一（设置页滑轨显示与编辑弹窗校验共用；2026-09-27 全局化笔加）：**不可复用
// resolveToolStepLimit**——它把 0 换算成硬顶 256，会把「不限制」在滑轨上显示成 256 轮。
// ≤0（含脏负数）= 0（与 resolveToolStepLimit 把 0 与负值都当「不限制」的口径一致）；1~MAX
// 四舍五入原值；超 MAX（脏数据）收口 MAX；非有限数（NaN/Infinity）回默认——脏持久值经
// 设置页 aboutToAppear 归正后由 @Watch 回写落盘（归正结果与滑轨当前值相同时不回写；消费侧
// 换算同源，未回写的脏值不影响显示与生效值，只是落盘值留到下次进页再归正）
export function clampToolStepLimitStored(stored: number): number {
  if (!Number.isFinite(stored)) {
    return TOOL_STEP_LIMIT_DEFAULT;
  }
  if (stored <= 0) {
    return 0;
  }
  return Math.min(Math.round(stored), TOOL_STEP_LIMIT_MAX);
}

// ── 工具定义预算与 description 分档降级（★ 2026-10-22 工具定义预算与占用可见笔，决明
// 拍板「只做一二」；任务书 = docs/任务书-工具定义预算与占用可见-20261022.md，代决 D1/D2/
// D3/D6）──判定落点 = ChatContextUsageCalc.collectTools 末尾单源收口（发送组装声明 / 面板
// 活算估算 / token 闸 / 执行「未声明不执行」四面同源；**禁在 ChatRoundAssembly /
// ChatStreamBase / RequestCompose 二次裁剪**——两处裁剪即「面板显示 A、实发 B」漂移面）。
// 降级只改喂给模型的那一份（照 SKILL_MANIFEST_DESC_MAX 判例口径）：注册表 / toolsJson
// 缓存 / 编辑页 / 导出备份中的 description 全文不动；parametersJson 是参数生成正确性的
// 根，任何档位都不截（schema 砍了模型产参就废）。超预算先全量 description 降档，仍超按
// collectTools 追加序逆序整件移除 MCP 工具（绑定列表尾端 server 先让位）；**内置与模式
// 驱动件永不被移除（红线）**，MCP 耗尽仍超则到顶返回。被移除工具若被模型调用，由
// ChatToolRoundCtrl「未声明工具不执行」闸以 error JSON 回执兜住，无需执行层新代码。
export const TOOL_DEFS_BUDGET_ENABLED: boolean = true;  // kill-switch（false = 零行为变化）
export const TOOL_DEFS_BUDGET_CHARS: number = 32000;    // 拼串总预算（D1，对齐 MCP_TOOL_RESULT_MAX_CHARS 量级）
export const TOOL_DEFS_DESC_TRIM: number = 120;         // 降档档位（D2，SKILL_MANIFEST_DESC_MAX 同判例）

// 预算函数极简入参（R7：本文件保持零 import 叶子——sse-assert / assert-ui-shape 单文件复制
// 直跑面，引 AiToolDef 即破复制；字段与 AiToolDef 同名同型，结构同构直接互认，调用侧把
// AiToolDef[] 直传）
export interface ToolDefsBudgetEntry {
  name: string;
  description: string;
  parametersJson: string;
}

// 预算产物：tools = 降级后的工具清单（喂给模型的那份）；trimmedCount = description 被截断
// 的件数；droppedServerNames = 每移除一件 MCP 工具记其服务器名段一条（同名重复出现 = 该
// server 被移除多件，面板按组计数得「M 件超预算未带」）；droppedCount = 其长度
export interface ToolDefsBudgetResult {
  tools: ToolDefsBudgetEntry[];
  trimmedCount: number;
  droppedCount: number;
  droppedServerNames: string[];
}

// MCP 三段名前缀私判与服务器名段反解（分别与 McpText.MCP_TOOL_NAME_PREFIX /
// McpText.serverNameOfMcpToolName 同值同式）：本文件零 import 纪律禁引彼件，故自带同值
// 私判 + 指源——同值关系由 assert-ctx-usage 直跑钉守（反解样本经 mcpToolNameOf 拼装再经
// 预算产物反解回原名），改一处须同笔改另一处，禁引出第二前缀族
const TOOL_DEFS_MCP_PREFIX: string = 'mcp__';

function mcpServerSegOfBudgetEntry(name: string): string {
  const rest: string = name.startsWith(TOOL_DEFS_MCP_PREFIX) ?
    name.substring(TOOL_DEFS_MCP_PREFIX.length) : name;
  const sep: number = rest.indexOf('__');
  return sep >= 0 ? rest.substring(0, sep) : rest;
}

// 拼串口径（R4）：与 ChatContextUsage.toolDefsJsonOf 逐字同源——每件 name + ' ' +
// description + ' ' + parametersJson、件间 '\n' 连接。这里只算**长度**不建串（发送链热
// 路径，逐件累加 = len(name) + 1 + len(description) + 1 + len(parametersJson)，加件间
// 分隔 (n-1) 个），口径等价性由 assert-ctx-usage 边界构造直跑钉守（钉在真 join 上验闸位）
function toolDefsJoinLenOf(tools: ToolDefsBudgetEntry[]): number {
  let total: number = 0;
  for (const t of tools) {
    total += t.name.length + 1 + t.description.length + 1 + t.parametersJson.length;
  }
  return tools.length > 0 ? total + tools.length - 1 : 0;
}

// 预算三段：不超原样（逐字节等、零拷贝）→ 全量 description 降档（> TRIM 截 TRIM）重算 →
// 仍超逆序整件移除 MCP 件（尾端优先；遇非 MCP 件即 MCP 耗尽，到顶返回不动内置）。
// 关态或限内 = 输入数组原引用直回（预算是重度配置才到的边界态闸，常见路径零分配）
export function applyToolDefsBudget(tools: ToolDefsBudgetEntry[]): ToolDefsBudgetResult {
  if (!TOOL_DEFS_BUDGET_ENABLED ||
    toolDefsJoinLenOf(tools) <= TOOL_DEFS_BUDGET_CHARS) {
    return { tools: tools, trimmedCount: 0, droppedCount: 0, droppedServerNames: [] };
  }
  let current: ToolDefsBudgetEntry[] = [];
  let trimmedCount: number = 0;
  for (const t of tools) {
    if (t.description.length > TOOL_DEFS_DESC_TRIM) {
      trimmedCount += 1;
      current.push({ name: t.name,
        description: t.description.substring(0, TOOL_DEFS_DESC_TRIM),
        parametersJson: t.parametersJson });
    } else {
      current.push(t);
    }
  }
  // 增量簿记：总长先一次算齐，每移除一件扣「该件长 + 1 个件间分隔」（数组长度 ≥1 时循环
  // 判据才生效，移空即停——末件移除时多扣的 1 个分隔不影响任何后续判定）
  let total: number = toolDefsJoinLenOf(current);
  const droppedServerNames: string[] = [];
  while (current.length > 0 && total > TOOL_DEFS_BUDGET_CHARS) {
    const last: ToolDefsBudgetEntry = current[current.length - 1];
    if (!last.name.startsWith(TOOL_DEFS_MCP_PREFIX)) {
      break;
    }
    droppedServerNames.push(mcpServerSegOfBudgetEntry(last.name));
    total -= last.name.length + 1 + last.description.length + 1 +
      last.parametersJson.length + 1;
    current = current.slice(0, current.length - 1);
  }
  return { tools: current, trimmedCount: trimmedCount,
    droppedCount: droppedServerNames.length, droppedServerNames: droppedServerNames };
}
