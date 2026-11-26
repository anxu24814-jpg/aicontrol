// 工具域聚合根——只管「工具是什么、怎么注册与分组」（RikkaHub / CubeAgent 调研定稿裁剪）：
// · 注册表（定义 + 执行器；启动注册幂等）+ 工具页分组元数据（TOOL_GROUP_* / toolGroups）+
//   助手启用清单解析/序列化（assistants.tools 列，DB v14——'' = 默认集合）+ 基础内置工具
//  （时间/提问）；各独立工具域实现分居同目录域件（ToolPrompts / ToolFunctional / ToolPref
//   / ToolUsageStats / ToolHelpSearch / ToolChatSearch / ToolMemoryManage / ToolSkill
//   / ToolProvider / ToolCostStats / ToolWebSearch / ToolHttp / ToolWorkspace / ToolMount
//   / ToolChart 等），本文件只注册；工具卡显示态判定簇在 ToolCardView.ets。
// · 新独立域注册面形态 = **域件自注册 + 组标签同居域件**（ToolMount / ToolChart 即此——域件
//   不能反向引聚合根，标签留本件则自注册无解；本件只留一字接线）。
// · 工具名常量在零依赖叶子 ToolIds.ets（解域件 ↔ 本文件模块环）；本文件不对外转出 id（禁加
//   `export { … } from './ToolIds'`），新增工具在该件加常量、本文件注册块引用；政策元数据
//  （modeDriven / webDomain / interactionKind）就地定义在各注册块——判据随注册项派生，
//   三名单字面量已退役（负向钉守零残留，勿重建第二份）。
// · 边界：协议方言（tools 注入与工具消息翻译）在 RequestCompose；流式解析 SseParser；流式
//   聚合 ToolStream、结果截断 ToolClip；执行域 ToolRuntime；多轮编排 ChatSendCtrl。
// ★ 2026-10-25 控制台合并笔（决明拍板）：控制台助手整体退役——原独占 13 件中 12 件开放给全部
//   助手、set_app_preference 写件退役（决明拍板「保留读取能力」——白名单保留为
//   get_app_preference 的范围单源）；consoleExclusive / consoleCore 字段与 isConsoleExclusive
//   / isConsoleAllowedForAssistant 两谓词同笔删除，启用面回归单层「助手工具页开关」，
//   写动作安全由确认链承接。

import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ToolEntry, ToolExecutor } from './ToolContracts';
import { toolRegistry } from './ToolRegistry';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { SearchWebExecutor, ScrapeWebExecutor } from './ToolWebSearch';
import { SearchHelpExecutor } from './ToolHelpSearch';
import { GetAppPreferenceExecutor, buildGetPrefDesc } from './ToolPref';
import { EditSystemPromptExecutor, ManagePromptsExecutor, EDIT_SYSTEM_PROMPT_SCHEMA,
  MANAGE_PROMPTS_SCHEMA, buildEditSystemPromptDesc, buildManagePromptsDesc,
  editSystemPromptNeedsConfirm, managePromptsNeedsConfirm } from './ToolPrompts';
import { EditTitlePromptExecutor, SetFunctionalModelExecutor, EDIT_TITLE_PROMPT_SCHEMA,
  SET_FUNCTIONAL_MODEL_SCHEMA, buildEditTitlePromptDesc, buildSetFunctionalModelDesc,
  setFunctionalModelNeedsConfirm } from './ToolFunctional';
import { GetUsageStatsExecutor, GET_USAGE_STATS_SCHEMA,
  buildGetUsageStatsDesc } from './ToolUsageStats';
import { SearchMemoryExecutor } from '../MemoryGen';
import { SearchChatsExecutor, GetChatsExecutor, GET_CHATS_SCHEMA, SEARCH_CHATS_SCHEMA,
  buildGetChatsDesc, buildSearchChatsDesc } from './ToolChatSearch';
import { ManageMemoryExecutor, MANAGE_MEMORY_SCHEMA,
  buildManageMemoryDesc, manageMemoryNeedsConfirm } from './ToolMemoryManage';
import { SearchKnowledgeExecutor, SEARCH_KNOWLEDGE_SCHEMA, buildSearchKnowledgeDesc,
  ManageKnowledgeExecutor, MANAGE_KNOWLEDGE_SCHEMA,
  buildManageKnowledgeDesc, manageKnowledgeNeedsConfirm } from './ToolKnowledge';
import { ManageSkillsExecutor, MANAGE_SKILLS_SCHEMA, buildManageSkillsDesc,
  UseSkillExecutor, USE_SKILL_SCHEMA } from './ToolSkill';
import { GetProviderConfigExecutor, GET_PROVIDER_CONFIG_SCHEMA,
  buildGetProviderConfigDesc } from './ToolProvider';
import { GetCostStatsExecutor, GET_COST_STATS_SCHEMA,
  buildGetCostStatsDesc } from './ToolCostStats';
import { BrowseOpenExecutor, BrowseReadExecutor, BROWSE_OPEN_DESC,
  BROWSE_OPEN_SCHEMA, BROWSE_READ_DESC, BROWSE_READ_SCHEMA } from './ToolBrowse';
import { BrowseActExecutor, BROWSE_ACT_DESC, BROWSE_ACT_SCHEMA,
  browseActNeedsConfirm, grantBrowseApproval } from './ToolBrowseAct';
import { BrowseSnapExecutor, BROWSE_SNAPSHOT_DESC, BROWSE_SNAPSHOT_SCHEMA } from './ToolBrowseSnap';
import { HttpRequestExecutor } from './ToolHttp';
// http_request 的 desc/schema/预检单源在 HttpPreflight——声明面新码自该件引（坑50 纪律）；
// ToolHttp 以 re-export 保持存量兼容
import { HTTP_REQUEST_DESC, HTTP_REQUEST_SCHEMA, httpRequestNeedsConfirm } from './HttpPreflight';
import { EnvListExecutor, ENV_LIST_DESC, ENV_LIST_SCHEMA } from './ToolEnv';
import { LocationExecutor, GET_LOCATION_SCHEMA,
  buildGetLocationDesc } from './ToolLocation';
import { GetCalendarEventsExecutor, CreateCalendarEventExecutor,
  UpdateCalendarEventExecutor, DeleteCalendarEventExecutor,
  GET_CALENDAR_EVENTS_SCHEMA, CREATE_CALENDAR_EVENT_SCHEMA,
  UPDATE_CALENDAR_EVENT_SCHEMA, DELETE_CALENDAR_EVENT_SCHEMA,
  buildGetCalendarEventsDesc, buildCreateCalendarEventDesc,
  buildUpdateCalendarEventDesc, buildDeleteCalendarEventDesc,
  createCalendarEventNeedsConfirm, updateCalendarEventNeedsConfirm,
  deleteCalendarEventNeedsConfirm } from './ToolCalendar';
import { ClipboardWriteExecutor, CLIPBOARD_WRITE_SCHEMA,
  buildClipboardWriteDesc } from './ToolClipboard';
import { WorkspaceImportExecutor, WorkspaceListExecutor, WorkspaceReadExecutor,
  WorkspaceWriteExecutor, WorkspaceMkdirExecutor, WorkspaceRenameExecutor,
  WorkspaceMoveExecutor, WorkspaceDeleteExecutor,
  WorkspaceGlobExecutor, WorkspaceGrepExecutor,
  WORKSPACE_IMPORT_DESC, WORKSPACE_IMPORT_SCHEMA,
  WORKSPACE_LIST_DESC, WORKSPACE_LIST_SCHEMA, WORKSPACE_READ_DESC, WORKSPACE_READ_SCHEMA,
  WORKSPACE_WRITE_DESC, WORKSPACE_WRITE_SCHEMA,
  WORKSPACE_MKDIR_DESC, WORKSPACE_MKDIR_SCHEMA,
  WORKSPACE_RENAME_DESC, WORKSPACE_RENAME_SCHEMA,
  WORKSPACE_MOVE_DESC, WORKSPACE_MOVE_SCHEMA,
  WORKSPACE_DELETE_DESC, WORKSPACE_DELETE_SCHEMA,
  WORKSPACE_WRITE_XLSX_DESC, WORKSPACE_WRITE_XLSX_SCHEMA,
  WORKSPACE_GLOB_DESC, WORKSPACE_GLOB_SCHEMA,
  WORKSPACE_GREP_DESC, WORKSPACE_GREP_SCHEMA,
  WorkspaceWriteXlsxExecutor,
  WorkspaceEditExecutor, WORKSPACE_EDIT_DESC, WORKSPACE_EDIT_SCHEMA,
  WorkspaceStageExecutor, WORKSPACE_STAGE_DESC, WORKSPACE_STAGE_SCHEMA,
  workspaceDeleteNeedsConfirm } from './ToolWorkspace';
// 压缩包三件（desc/schema/执行器在 ToolZip.ets——容器解析纯核在 common/workspace/
// ZipArchiveCore.ets，零 ToolTypes 引用防环同上）
import { ZipListExecutor, ZipExtractExecutor, ZipCreateExecutor,
  ZIP_LIST_DESC, ZIP_LIST_SCHEMA,
  ZIP_EXTRACT_DESC, ZIP_EXTRACT_SCHEMA,
  ZIP_CREATE_DESC, ZIP_CREATE_SCHEMA } from './ToolZip';
// Office 补丁单件（desc/schema/执行器在 ToolOffice.ets——改写纯核在 common/workspace/
// OoxmlPatchCore.ets，零 ToolTypes 引用防环同上）
import { OfficePatchExecutor, OFFICE_PATCH_DESC, OFFICE_PATCH_SCHEMA } from './ToolOffice';
// 挂载六件 = ToolMount.ets 自注册域件（组标签同居该件，本件只接线）
import { registerMountTools, TOOL_GROUP_MOUNT } from './ToolMount';
// Python 单件 = ToolPyExec.ets 自注册域件（组标签同居该件，本件只接线——门 4 笔；与代码
// 工作台平行的执行域：JS 沙箱 vs 内嵌 CPython，两卡互不联动）
import { registerPyTools, TOOL_GROUP_PYTHON } from './ToolPyExec';
// Node 执行域（门 2）：exec_node 自注册件——组标签同居本件，此处只接线（组序紧随 Python）
import { registerNodeTools, TOOL_GROUP_NODE } from './ToolNodeExec';
// 图表单件 = ToolChart.ets 自注册域件（组标签同居该件，本件只接线）
import { registerChartTools, TOOL_GROUP_CHART } from './ToolChart';
import { ExecCodeExecutor, ExecOutputReadExecutor,
  EXEC_CODE_DESC, EXEC_CODE_SCHEMA,
  EXEC_OUTPUT_READ_DESC, EXEC_OUTPUT_READ_SCHEMA } from './ToolCodeExec';
import { ManageProvidersExecutor, MANAGE_PROVIDERS_SCHEMA,
  buildManageProvidersDesc, manageProvidersNeedsConfirm } from './ToolProviderAdmin';
import { ManageModelsExecutor, MANAGE_MODELS_SCHEMA,
  buildManageModelsDesc, manageModelsNeedsConfirm } from './ToolModelAdmin';
import { ManageBalanceExecutor, TestProviderExecutor, MANAGE_BALANCE_SCHEMA,
  TEST_PROVIDER_SCHEMA, buildManageBalanceDesc, buildTestProviderDesc,
  manageBalanceNeedsConfirm } from './ToolProviderProbe';

import { TOOL_GET_TIME_INFO, TOOL_ASK_USER, TOOL_SEARCH_WEB, TOOL_SCRAPE_WEB,
  TOOL_BROWSE_OPEN, TOOL_BROWSE_READ, TOOL_BROWSE_ACT, TOOL_BROWSE_SCREENSHOT,
  TOOL_HTTP_REQUEST,
  TOOL_ENV_LIST,
  TOOL_SEARCH_HELP, TOOL_GET_APP_PREFERENCE,
  TOOL_EDIT_SYSTEM_PROMPT, TOOL_MANAGE_PROMPTS, TOOL_SET_FUNCTIONAL_MODEL,
  TOOL_EDIT_TITLE_PROMPT, TOOL_GET_USAGE_STATS, TOOL_SEARCH_MEMORY, TOOL_SEARCH_CHATS,
  TOOL_GET_CHATS, TOOL_SEARCH_KNOWLEDGE, TOOL_MANAGE_KNOWLEDGE, TOOL_MANAGE_MEMORY,
  TOOL_USE_SKILL, TOOL_MANAGE_SKILLS, TOOL_GET_PROVIDER_CONFIG, TOOL_GET_COST_STATS,
  TOOL_GET_LOCATION, TOOL_WORKSPACE_LIST, TOOL_WORKSPACE_READ,
  TOOL_WORKSPACE_WRITE, TOOL_WORKSPACE_IMPORT,
  TOOL_WORKSPACE_MKDIR, TOOL_WORKSPACE_RENAME,
  TOOL_WORKSPACE_MOVE, TOOL_WORKSPACE_DELETE,
  TOOL_WORKSPACE_WRITE_XLSX, TOOL_WORKSPACE_GLOB, TOOL_WORKSPACE_GREP,
  TOOL_WORKSPACE_EDIT, TOOL_WORKSPACE_STAGE,
  TOOL_ZIP_LIST, TOOL_ZIP_EXTRACT, TOOL_ZIP_CREATE,
  TOOL_OFFICE_PATCH,
  TOOL_EXEC_CODE, TOOL_EXEC_OUTPUT_READ,
  TOOL_MANAGE_PROVIDERS, TOOL_MANAGE_MODELS, TOOL_TEST_PROVIDER,
  TOOL_MANAGE_BALANCE,
  TOOL_GET_CALENDAR_EVENTS, TOOL_CREATE_CALENDAR_EVENT,
  TOOL_UPDATE_CALENDAR_EVENT, TOOL_DELETE_CALENDAR_EVENT,
  TOOL_CLIPBOARD_WRITE } from './ToolIds';

const DOMAIN: number = 0x0001;
const TAG: string = 'ToolTypes';

// ── 工具政策判据（随注册项派生；函数首行调 registerBuiltinTools() 自足——调用方未先注册
//    也能得正确结果）──
// · 模式驱动（modeDriven）= 声明由全局模式开关决定、不走 assistants.tools 启用清单（现三件：
//   search_memory / use_skill / env_list）；工具页按本判据过滤不出页——「模式开关 × 工具页
//   开关」双重控制会打架（模式关时页上开了也不生效、开时页上没开也照常声明，两处真相互相矛盾）。
// · 联网域（webDomain）= 随联网域可用性（助手清单 ∩ 会话「联网」开关）同进同出。口径：
//   **声明层全剔域内各件**（ChatSendCtrl 过滤表达式）；**UI 压制剔从属件** =
//   isWebDomainTool(name) && name !== TOOL_SEARCH_WEB（AssistantToolsPage.isToolSuppressed）
//   ——search_web 是域主件（它本身就是那个开关），不做自压制。新独立域照 http_request /
//   浏览器控制两先例：出名单 + 单列 TOOL_GROUP_* 卡。
export function isModeDriven(name: string): boolean {
  registerBuiltinTools();
  return toolRegistry.get(name)?.modeDriven === true;
}

export function isWebDomainTool(name: string): boolean {
  registerBuiltinTools();
  return toolRegistry.get(name)?.webDomain === true;
}

// isCodeWorkbenchTool 判定已随全局总开关退役（2026-10-06）——无全局键即无派生判定的存在对象

// 交互类别派生：加新的交互式工具只需在其注册块标 interactionKind: INTERACTION_ASK，
// 编排层零改动；未知名同缺省（存在性校验由「未声明即不执行」守卫承担，不归本函数）
export function toolInteractionKind(name: string): string {
  registerBuiltinTools();
  const kind: string | undefined = toolRegistry.get(name)?.interactionKind;
  return kind !== undefined ? kind : INTERACTION_DIRECT;
}

// 搜索类结果统一 JSON 载荷（SearchResultItemPayload / SearchResultOutputPayload）在 ToolWebSearch.ets
//（ChatToolCard 引文卡自该件引 payload）

// ToolExecutor 契约在 ToolContracts.ets（聚合根反向成环风险详见该件头注释）；本文件按需引
// 且不对外转出（转出会把环接回来）

// 交互类别取值（ToolEntry.interactionKind）：'ask' = 该工具要与用户往返（工具轮整轮串行 +
// 走交互桥），'direct' = 直通注册表执行器（缺省）；消费方均经 toolInteractionKind 派生
export const INTERACTION_ASK: string = 'ask';
export const INTERACTION_DIRECT: string = 'direct';

// ── 注册表容器在 ToolRegistry.ets；本文件转出 ToolEntry / ToolRegistry / toolRegistry 三标识
//    仅为存量 import 兼容（照 MemoryGen / AiTypes 先例），新码契约一律自叶子引，勿经本文件 ──
export { ToolEntry } from './ToolContracts';
export { ToolRegistry, toolRegistry } from './ToolRegistry';

// registerBuiltinTools 首用标记（幂等守卫）
let builtinRegistered: boolean = false;


// 函数名 → 展示名（工具卡标题用；未注册函数名原样返回——未知/自定义工具可读性兜底）
export function toolTitle(name: string): string {
  registerBuiltinTools();
  const entry: ToolEntry | undefined = toolRegistry.get(name);
  return entry !== undefined ? entry.title : name;
}

// ── 工具页分组（本文件管分组元数据；卡显示态判定在 ToolCardView.ets，卡面副标题与图标在
//    AssistantToolsPage）──

// 组标题（功能卡轴唯一来源，一卡一枚开关；组序 = TOOL_GROUP_ORDER，页面按此渲染）。分卡判据：
// · 敏感面（定位/日程）独立成卡显式单开，不被基础能力整卡开关捎带授权；
// · 平行能力域各成一卡、启用面互不牵连（HTTP 请求 / 浏览器控制自联网搜索独立；文件夹挂载
//   与文件工作区是平行的两个文件域；代码工作台脚本族自工作区拆出）；
// · 记忆 / 知识库自「本地检索」剥出各成一卡（同为「给模型的知识面」，组序插本地检索之前）；
// · 应用管理卡收配置类工具（原独占件卡，2026-10-25 起普通助手可见可开）。
export const TOOL_GROUP_BASIC: string = '基础能力';
export const TOOL_GROUP_LOCATION: string = '位置';
// 日程卡：四件（查询/创建/修改/删除）——只读写本应用创建的日程，敏感面全部默认关
export const TOOL_GROUP_CALENDAR: string = '日程';
// 剪贴板卡：写入单件——零权限、默认关。读剪贴板未做（READ_PASTEBOARD 属受限开放权限，
// 官方白名单不含 AI 助手——决明拍板只做零权限写入，见 ToolClipboard.ets 头注释）
export const TOOL_GROUP_CLIPBOARD: string = '剪贴板';
// 图表卡：chart_display 单件（把数据画成图表显示在对话里），defaultEnabled=false 显式开；
// 常量本体与注册块同居自注册域件 ToolChart.ets，本处仅引回入下方组序数组
export const TOOL_GROUP_WEB: string = '联网搜索';
export const TOOL_GROUP_BROWSE: string = '浏览器控制';
export const TOOL_GROUP_HTTP: string = 'HTTP 请求';
export const TOOL_GROUP_WORKSPACE: string = '文件工作区';
// 文件夹挂载卡：常量本体随注册块同居 ToolMount.ets（自注册域件组标签），本处仅引回入组序；
// 与文件工作区是平行的两个文件域（沙箱域 vs 授权外部域），组序相邻；与挂载行级「允许 AI
// 使用」开关构成双层门（组开关 = 该助手可否用挂载工具族）
// 脚本工作台卡：三件脚本族（exec_code / exec_output_read / workspace_stage）——域内聚
//（stage 唯一消费方是脚本沙箱），可用性全权随本卡开关；组序插文件工作区之后（能力域相邻）。
// ★ 2026-11-16 改题：原「代码工作台」→「脚本工作台」（决明拍板，与设置页标题单源同步；
// 理由 = 「代码」语义过宽，本卡只含 JavaScript 与模拟 Shell 两模式，Python 另有独立卡）
export const TOOL_GROUP_CODE: string = '脚本工作台';
// Python 运行卡：常量本体随注册块同居 ToolPyExec.ets（自注册域件组标签），本处仅引回入
// 组序；紧邻脚本工作台之后（能力域相邻，拍板「默认关、互不联动」）
export const TOOL_GROUP_MEMORY: string = '记忆';
export const TOOL_GROUP_KNOWLEDGE: string = '知识库';
export const TOOL_GROUP_LOCAL: string = '本地检索';
export const TOOL_GROUP_SKILL: string = '技能管理';
export const TOOL_GROUP_APP: string = '应用管理';
const TOOL_GROUP_ORDER: string[] = [TOOL_GROUP_BASIC, TOOL_GROUP_LOCATION, TOOL_GROUP_CALENDAR,
  TOOL_GROUP_CLIPBOARD, TOOL_GROUP_CHART,
  TOOL_GROUP_WEB, TOOL_GROUP_BROWSE, TOOL_GROUP_HTTP, TOOL_GROUP_WORKSPACE,
  TOOL_GROUP_MOUNT, TOOL_GROUP_CODE, TOOL_GROUP_PYTHON, TOOL_GROUP_NODE,
  TOOL_GROUP_MEMORY, TOOL_GROUP_KNOWLEDGE, TOOL_GROUP_LOCAL, TOOL_GROUP_SKILL,
  TOOL_GROUP_APP];

// 分组视图条目（页面渲染源：组标题 + 成员按注册序）
export interface ToolGroup {
  title: string;
  members: ToolEntry[];
}

// 注册表分组视图（工具页渲染源）：按 TOOL_GROUP_ORDER 组序、组内注册序；空组不出现
//（新增域 = 常量 + 组序 + 各工具 group 标注三处，页面零改动）
export function toolGroups(): ToolGroup[] {
  registerBuiltinTools();
  const all: ToolEntry[] = toolRegistry.all();
  const groups: ToolGroup[] = [];
  for (const title of TOOL_GROUP_ORDER) {
    const members: ToolEntry[] = [];
    for (const entry of all) {
      if (entry.group === title) {
        members.push(entry);
      }
    }
    if (members.length > 0) {
      groups.push({ title: title, members: members });
    }
  }
  return groups;
}

// ── 工具卡显示态判定（visibleToolGroups / isToolSuppressedInList / isToolEnablable 等）已整段
//    外迁 ToolCardView.ets——消费方（AssistantToolsPage / AssistantEditPage 等）import 自该件；
//    toolGroups 分组视图与 TOOL_GROUP_* 常量仍归本件（分组元数据主域）──

// ── 内置工具执行器 ──

// 获取当前时间：本地日期/星期/时间/时区/时间戳；无参数工具（schema 空 object——防 provider
// 校验空参缺 type）
class GetTimeInfoExecutor implements ToolExecutor {
  execute(_argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    const now: Date = new Date();
    const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    const info: TimeInfoResult = {
      date: `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`,
      time: `${now.getHours()}:${now.getMinutes().toString().padStart(2, '0')}`,
      weekday: '星期' + weekdays[now.getDay()],
      timezone: '',
      timestampMs: now.getTime()
    };
    try {
      info.timezone = i18n.getTimeZone().getID();
    } catch (e) {
      info.timezone = ''; // 时区读取失败留空（结果文本仍可用——不阻断）
    }
    return Promise.resolve(JSON.stringify(info));
  }
}

// 时间工具结果（ArkTS 对象字面量挂显式接口——坑59①）
interface TimeInfoResult {
  date: string;
  time: string;
  weekday: string;
  timezone: string;
  timestampMs: number;
}

// 向用户提问占位执行器：真实路径在 ChatSendCtrl 工具执行轮拦交 ToolRuntime.waitAsk
//（挂起等用户作答——交互式工具不走 executor）。注册占位仅防漏网直调（返回错误 JSON 可观测）
class AskUserPlaceholderExecutor implements ToolExecutor {
  execute(_argsJson: string, _ctx: ToolExecutionContext): Promise<string> {
    return Promise.resolve(JSON.stringify({ error: 'ask_user 应走交互桥，占位执行器不可达' }));
  }
}

// ask_user 入参 schema（rawSchema 原串注入——ArkTS 禁无类型对象字面量）；多问上限 5 与
// options 上限 4 与卡面 ASK_OPTIONS_MAX 同源
const ASK_USER_SCHEMA: string = '{"type":"object","properties":{"questions":{"type":"array",' +
  '"minItems":1,"maxItems":5,"items":{"type":"object","properties":{' +
  '"id":{"type":"string","description":"问题唯一短 id，例如 q1"},"question":{"type":"string",' +
  '"description":"要问用户的问题，一句话，需要澄清什么就问什么"},' +
  '"options":{"type":"array","items":{"type":"string"},"maxItems":4,' +
  '"description":"可给用户点选的选项，2~4 个。能给选项时尽量给，用户也可以自己写"},' +
  '"selection_type":{"type":"string","enum":["single","multi","text"],' +
  '"description":"选项形态。single 单选，multi 多选，text 纯文本；给了 options 必须给本字段，缺省 text"}},' +
  '"required":["id","question"]}}},' +
  '"required":["questions"]}';

// 内置工具注册（启动首用调一次；幂等守卫防重复覆盖）
export function registerBuiltinTools(): void {
  if (builtinRegistered) {
    return;
  }
  builtinRegistered = true;
  toolRegistry.register({
    name: TOOL_GET_TIME_INFO,
    group: TOOL_GROUP_BASIC,
    title: '获取当前时间',
    desc: '返回设备当前本地日期、时间、星期、时区与时间戳，供模型回答与时间相关的问题。',
    parametersJson: '{"type":"object","properties":{}}',
    defaultEnabled: true,
    executor: new GetTimeInfoExecutor()
  });
  // 获取当前位置（执行器在 ToolLocation.ets）：敏感面必须显式单开——独立「位置」卡 +
  // defaultEnabled=false（决明拍板「默认关」——true = 任何助手开箱即得定位能力，不可接受）；
  // 无 preflight——只读本地定位，系统授权弹窗即用户同意闸（拒绝走错误文案）
  toolRegistry.register({
    name: TOOL_GET_LOCATION,
    group: TOOL_GROUP_LOCATION,
    title: '获取当前位置',
    desc: buildGetLocationDesc(),
    parametersJson: GET_LOCATION_SCHEMA,
    defaultEnabled: false,
    executor: new LocationExecutor()
  });
  // 日程四件（执行器在 ToolCalendar.ets）：只读写本应用创建的日程（自建账户写入系统日历，
  // 用户可见）；敏感面四件 defaultEnabled=false 全部不进默认集合（用户显式开）；权限 =
  // READ/WRITE_CALENDAR 双 user_grant，执行器先查后申（域件头注释）。确认链：创建/修改 =
  // 写档（三键卡）、删除 = 不可逆档（恒问人）——三写件带 preflight，读件零 preflight
  toolRegistry.register({
    name: TOOL_GET_CALENDAR_EVENTS,
    group: TOOL_GROUP_CALENDAR,
    title: '查询日程',
    desc: buildGetCalendarEventsDesc(),
    parametersJson: GET_CALENDAR_EVENTS_SCHEMA,
    defaultEnabled: false,
    executor: new GetCalendarEventsExecutor()
  });
  toolRegistry.register({
    name: TOOL_CREATE_CALENDAR_EVENT,
    group: TOOL_GROUP_CALENDAR,
    title: '创建日程',
    desc: buildCreateCalendarEventDesc(),
    parametersJson: CREATE_CALENDAR_EVENT_SCHEMA,
    defaultEnabled: false,
    preflight: createCalendarEventNeedsConfirm,
    executor: new CreateCalendarEventExecutor()
  });
  toolRegistry.register({
    name: TOOL_UPDATE_CALENDAR_EVENT,
    group: TOOL_GROUP_CALENDAR,
    title: '修改日程',
    desc: buildUpdateCalendarEventDesc(),
    parametersJson: UPDATE_CALENDAR_EVENT_SCHEMA,
    defaultEnabled: false,
    preflight: updateCalendarEventNeedsConfirm,
    executor: new UpdateCalendarEventExecutor()
  });
  toolRegistry.register({
    name: TOOL_DELETE_CALENDAR_EVENT,
    group: TOOL_GROUP_CALENDAR,
    title: '删除日程',
    desc: buildDeleteCalendarEventDesc(),
    parametersJson: DELETE_CALENDAR_EVENT_SCHEMA,
    defaultEnabled: false,
    preflight: deleteCalendarEventNeedsConfirm,
    executor: new DeleteCalendarEventExecutor()
  });
  // 写入剪贴板（执行器在 ToolClipboard.ets）：零权限，写路径经 common/Clipboard 单源；
  // defaultEnabled=false 显式开；零 preflight（决明拍板不弹确认卡——描述句防线 + 默认关 +
  // 工具卡可见结果，照 rikkahub/kelivo 参考；写入替换式，见域件头注释）
  toolRegistry.register({
    name: TOOL_CLIPBOARD_WRITE,
    group: TOOL_GROUP_CLIPBOARD,
    title: '写入剪贴板',
    desc: buildClipboardWriteDesc(),
    parametersJson: CLIPBOARD_WRITE_SCHEMA,
    defaultEnabled: false,
    executor: new ClipboardWriteExecutor()
  });
  // 图表单件注册块在 ToolChart.ets 自注册（本处只接线；序位与组序数组一致）
  registerChartTools();
  toolRegistry.register({
    name: TOOL_ASK_USER,
    interactionKind: INTERACTION_ASK,
    group: TOOL_GROUP_BASIC,
    title: '向用户提问',
    desc: '模型需要澄清时向你发起的提问，你的答复会作为工具结果回给模型继续生成。能给选项时请给选项，用户也可以自己写。',
    parametersJson: ASK_USER_SCHEMA,
    defaultEnabled: true,
    executor: new AskUserPlaceholderExecutor()
  });
  // 联网搜索双工具：description 含引用规范原文——分工原则「工具细节全在 description，
  // 系统提示词只留通用规则」（能力单源在 desc 红线）
  toolRegistry.register({
    name: TOOL_SEARCH_WEB,
    webDomain: true,
    group: TOOL_GROUP_WEB,
    title: '联网搜索',
    desc: 'Search the web for up-to-date, specific, or verifiable information. First decide whether web access is truly needed; use your own knowledge for common stable facts and pure generation tasks. Each search has real cost, so generate focused keywords and run multiple searches only when more evidence is needed. Cite used sources as standard Markdown links like [title](url), not bare [1] or [2] numbers. Zero results or a missing-key error is final: do not repeat the same query; for key errors, tell the user to configure the engine in Settings.',
    parametersJson: '{"type":"object","properties":{"query":{"type":"string",' +
      '"description":"聚焦搜索关键词，例如 比亚迪 海豹 续航。用于搜索外部实时、特定或需要验证的信息，不要传入整段用户问题。"}}, "required":["query"]}',
    defaultEnabled: true,
    executor: new SearchWebExecutor()
  });
  toolRegistry.register({
    name: TOOL_SCRAPE_WEB,
    webDomain: true,
    group: TOOL_GROUP_WEB,
    title: '读取网页',
    // ★ 2026-11-01 分页续读笔：desc 补续读教学（长页分段返回，nextOffset 在场时带 offset
    // 续读）——与 ToolWebSearch 执行器分页形制同笔对应
    desc: 'Scrape a URL for detailed page content. Use this when the user provides a specific URL, asks to read or summarize a page, or search snippets are insufficient. Avoid using it for common questions unless the user asks. Long pages are returned in parts: the response carries totalLength and, while more text remains, nextOffset. To keep reading, call again with offset set to the previous nextOffset instead of re-fetching from the beginning.',
    parametersJson: '{"type":"object","properties":{"url":{"type":"string",' +
      '"description":"要读取的网页 URL。用户给出 URL 或要求总结、分析某个网页时，原样传入 URL。"},' +
      '"offset":{"type":"integer","description":"续读起始字符位置。首次读取不传；要继续读后文时传上一次回执里的 nextOffset 值。"}}, "required":["url"]}',
    defaultEnabled: true,
    executor: new ScrapeWebExecutor()
  });
  // 内置浏览器双工具（执行器在 ToolBrowse.ets）：browse_open 后台隐形 Web 打开网页读渲染后
  // 正文（ArkWeb AI 页面命令 getLiteDom），browse_read 续读正文或取可交互元素清单；独立
  //「浏览器控制」卡、默认开维持（防存量空清单助手能力静默缩水），不随联网闸门
  toolRegistry.register({
    name: TOOL_BROWSE_OPEN,
    group: TOOL_GROUP_BROWSE,
    title: '打开网页',
    desc: BROWSE_OPEN_DESC,
    parametersJson: BROWSE_OPEN_SCHEMA,
    defaultEnabled: true,
    executor: new BrowseOpenExecutor()
  });
  toolRegistry.register({
    name: TOOL_BROWSE_READ,
    group: TOOL_GROUP_BROWSE,
    title: '浏览当前页',
    desc: BROWSE_READ_DESC,
    parametersJson: BROWSE_READ_SCHEMA,
    defaultEnabled: true,
    executor: new BrowseReadExecutor()
  });
  // 操作网页（执行器在 ToolBrowseAct.ets）：对当前页执行 scroll/click/type/select/press_key
  //（官方 AIPageInteraction 协议）；高危动作静态拦截（词表 + password/submit 属性，恒拒）；
  // settle 有界采样后重拍覆写页态
  toolRegistry.register({
    name: TOOL_BROWSE_ACT,
    group: TOOL_GROUP_BROWSE,
    title: '操作网页',
    desc: BROWSE_ACT_DESC,
    parametersJson: BROWSE_ACT_SCHEMA,
    defaultEnabled: true,
    executor: new BrowseActExecutor(),
    // 确认链接线：preflight 预检收集 + onApproved 允许后授予（注册表分发）
    preflight: browseActNeedsConfirm,
    onApproved: (convId: string): void => { grantBrowseApproval(convId); }
  });
  // 网页截图（执行器在 ToolBrowseSnap.ets）：视口截图 + 整页双通道（构建期开关默认关）；
  // 只读零确认（同卡零 preflight 先例）
  toolRegistry.register({
    name: TOOL_BROWSE_SCREENSHOT,
    group: TOOL_GROUP_BROWSE,
    title: '网页截图',
    desc: BROWSE_SNAPSHOT_DESC,
    parametersJson: BROWSE_SNAPSHOT_SCHEMA,
    defaultEnabled: true,
    executor: new BrowseSnapExecutor()
  });
  // HTTP 请求（执行器在 ToolHttp.ets / HttpPreflight）：独立卡无联网闸门——启用面只由本卡
  // 开关决定（会话「联网」开关不影响本件）；defaultEnabled=false（true = 静默向存量助手发放
  // 写能力，不可接受，须工具页手动开）；写方法（POST/PUT/DELETE/PATCH）经 preflight 逐次确认
  //（设置 → 工具调用页「HTTP 写操作确认」卡可切「自动通过」）；★ 不带 onApproved——批准戳
  // 是 browse_act 执行器免戳闸的专属凭据，跨工具写戳 = 语义污染 + 未来第三件带戳工具的误
  // 消费口子（安全语义钉③负向钉守）
  toolRegistry.register({
    name: TOOL_HTTP_REQUEST,
    group: TOOL_GROUP_HTTP,
    title: 'HTTP 请求',
    desc: HTTP_REQUEST_DESC,
    parametersJson: HTTP_REQUEST_SCHEMA,
    defaultEnabled: false,
    executor: new HttpRequestExecutor(),
    preflight: httpRequestNeedsConfirm
  });
  // HTTP 凭据查名（执行器在 ToolEnv.ets）：★ 模式驱动第三件——声明不走 assistants.tools，
  // 助手启用清单含 http_request 时由 ChatContextUsage.collectTools 追加（与 http_request
  // 同进退）；工具页按 isModeDriven 过滤不出页（HTTP 卡保持单件、卡态不虚报）；回执只含
  // 名称清单，值永不出现在对话（硬边界，详见 ToolEnv 头注释）
  toolRegistry.register({
    name: TOOL_ENV_LIST,
    modeDriven: true,
    group: TOOL_GROUP_HTTP,
    title: 'HTTP 凭据清单',
    desc: ENV_LIST_DESC,
    parametersJson: ENV_LIST_SCHEMA,
    defaultEnabled: false,
    executor: new EnvListExecutor()
  });
  // 文件工作区三工具（执行器在 ToolWorkspace.ets）：工作区 = 应用内给助手读写文件的独立
  // 空间（与对话附件互不相通、不随删会话级联、不进备份）；defaultEnabled=false 显式开；
  // 无 preflight（写入可逆、用户可在管理页删——§8-8 拍板不进确认链）；模型侧无删除工具
  //（删除只在用户管理面）
  toolRegistry.register({
    name: TOOL_WORKSPACE_LIST,
    group: TOOL_GROUP_WORKSPACE,
    title: '列出工作区文件',
    desc: WORKSPACE_LIST_DESC,
    parametersJson: WORKSPACE_LIST_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceListExecutor()
  });
  toolRegistry.register({
    name: TOOL_WORKSPACE_READ,
    group: TOOL_GROUP_WORKSPACE,
    title: '读取工作区文件',
    desc: WORKSPACE_READ_DESC,
    parametersJson: WORKSPACE_READ_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceReadExecutor()
  });
  toolRegistry.register({
    name: TOOL_WORKSPACE_WRITE,
    group: TOOL_GROUP_WORKSPACE,
    title: '保存到工作区',
    desc: WORKSPACE_WRITE_DESC,
    parametersJson: WORKSPACE_WRITE_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceWriteExecutor()
  });
  // 会话附件按名导入工作区（同名覆盖、单件 30MB、不弹确认照 write 定案）；不进 ToolPref
  // 白名单（本域零模型可写设置）
  toolRegistry.register({
    name: TOOL_WORKSPACE_IMPORT,
    group: TOOL_GROUP_WORKSPACE,
    title: '附件存入工作区',
    desc: WORKSPACE_IMPORT_DESC,
    parametersJson: WORKSPACE_IMPORT_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceImportExecutor()
  });
  // 目录四工具——mkdir / rename / move / delete（模型侧目录管理面）；同族注册形态
  // defaultEnabled=false；**仅 delete 带 preflight**（不可逆档——删除每次先征求用户同意，
  // 任何数据管理档位都恒问人，照 manage_knowledge 先例）；mkdir/rename/move 可逆照 §8-8
  // 拍板不弹确认；delete 不带 onApproved（无免戳闸消费面，照 http_request 同款理由）
  toolRegistry.register({
    name: TOOL_WORKSPACE_MKDIR,
    group: TOOL_GROUP_WORKSPACE,
    title: '新建工作区文件夹',
    desc: WORKSPACE_MKDIR_DESC,
    parametersJson: WORKSPACE_MKDIR_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceMkdirExecutor()
  });
  toolRegistry.register({
    name: TOOL_WORKSPACE_RENAME,
    group: TOOL_GROUP_WORKSPACE,
    title: '重命名工作区条目',
    desc: WORKSPACE_RENAME_DESC,
    parametersJson: WORKSPACE_RENAME_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceRenameExecutor()
  });
  toolRegistry.register({
    name: TOOL_WORKSPACE_MOVE,
    group: TOOL_GROUP_WORKSPACE,
    title: '移动工作区条目',
    desc: WORKSPACE_MOVE_DESC,
    parametersJson: WORKSPACE_MOVE_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceMoveExecutor()
  });
  toolRegistry.register({
    name: TOOL_WORKSPACE_DELETE,
    group: TOOL_GROUP_WORKSPACE,
    title: '删除工作区条目',
    desc: WORKSPACE_DELETE_DESC,
    parametersJson: WORKSPACE_DELETE_SCHEMA,
    defaultEnabled: false,
    preflight: workspaceDeleteNeedsConfirm,
    executor: new WorkspaceDeleteExecutor()
  });
  // xlsx 生成工具——表格数据 JSON 二维数组 → 真 Excel 文件（产出核与落库编排见域件，桥页
  // 反读自检坏件永不落库）；零 preflight（可逆照 §8-8 先例——用户可在管理页删）
  toolRegistry.register({
    name: TOOL_WORKSPACE_WRITE_XLSX,
    group: TOOL_GROUP_WORKSPACE,
    title: '生成 Excel 表格',
    desc: WORKSPACE_WRITE_XLSX_DESC,
    parametersJson: WORKSPACE_WRITE_XLSX_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceWriteXlsxExecutor()
  });
  // 检索两工具——workspace_glob 按名称模式查找文件与文件夹（glob→RegExp 五规则 + 无 /
  // 模式 basename 兜底，500 上限字典序；主路 = DB 行集内存匹配零物理枚举）/
  // workspace_grep 在文本文件内容里搜索正则（只扫 text 档；三重闸 2MB/4MB/100；非法正则
  // 回退字面量）；只读零 preflight
  toolRegistry.register({
    name: TOOL_WORKSPACE_GLOB,
    group: TOOL_GROUP_WORKSPACE,
    title: '查找工作区文件',
    desc: WORKSPACE_GLOB_DESC,
    parametersJson: WORKSPACE_GLOB_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceGlobExecutor()
  });
  toolRegistry.register({
    name: TOOL_WORKSPACE_GREP,
    group: TOOL_GROUP_WORKSPACE,
    title: '搜索工作区文件内容',
    desc: WORKSPACE_GREP_DESC,
    parametersJson: WORKSPACE_GREP_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceGrepExecutor()
  });
  // workspace_edit 对既有文本文件做定点替换编辑（执行器在 ToolWorkspace.ets）：匹配 = 三级
  // 级联（exact → line_trimmed → block_anchor）+ reindent 缩进重排；**先读后编硬门**（本会话
  // read 过且行值未变才放行）；直写无备份（拍板）；零 preflight（编辑就地改既有行、管理页可删）
  toolRegistry.register({
    name: TOOL_WORKSPACE_EDIT,
    group: TOOL_GROUP_WORKSPACE,
    title: '编辑工作区文件',
    desc: WORKSPACE_EDIT_DESC,
    parametersJson: WORKSPACE_EDIT_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceEditExecutor()
  });
  // workspace_stage 入向桥——把工作区件（含二进制）拷贝进本会话临时区交给脚本处理（出向 =
  // fs.save 转正既有）；store 编排在 WorkspaceDbTmp.stageWorkspaceFileToTmp（拷贝语义、
  // 零落库、源零改动）；group = TOOL_GROUP_CODE（唯一消费方是脚本沙箱——「放入临时区」
  // 无脚本可给即无意义）；零 preflight（拷贝可逆、源只读、临时区可清）
  toolRegistry.register({
    name: TOOL_WORKSPACE_STAGE,
    group: TOOL_GROUP_CODE,
    title: '放入脚本临时区',
    desc: WORKSPACE_STAGE_DESC,
    parametersJson: WORKSPACE_STAGE_SCHEMA,
    defaultEnabled: false,
    executor: new WorkspaceStageExecutor()
  });
  // 压缩包三件（执行器在 ToolZip.ets，容器解析纯核在 common/workspace/ZipArchiveCore.ets
  // ——zip_list 条目清单 / zip_extract 解压吸入 / zip_create 文件夹打包）；归「文件工作区」
  // 卡尾段；零 preflight（产物可逆、用户可在管理页删——照 write 族 §8-8 拍板）
  toolRegistry.register({
    name: TOOL_ZIP_LIST,
    group: TOOL_GROUP_WORKSPACE,
    title: '查看压缩包清单',
    desc: ZIP_LIST_DESC,
    parametersJson: ZIP_LIST_SCHEMA,
    defaultEnabled: false,
    executor: new ZipListExecutor()
  });
  toolRegistry.register({
    name: TOOL_ZIP_EXTRACT,
    group: TOOL_GROUP_WORKSPACE,
    title: '解压压缩包',
    desc: ZIP_EXTRACT_DESC,
    parametersJson: ZIP_EXTRACT_SCHEMA,
    defaultEnabled: false,
    executor: new ZipExtractExecutor()
  });
  toolRegistry.register({
    name: TOOL_ZIP_CREATE,
    group: TOOL_GROUP_WORKSPACE,
    title: '打包文件夹',
    desc: ZIP_CREATE_DESC,
    parametersJson: ZIP_CREATE_SCHEMA,
    defaultEnabled: false,
    executor: new ZipCreateExecutor()
  });
  // Office 补丁件（执行器在 ToolOffice.ets，改写纯核在 common/workspace/OoxmlPatchCore.ets
  // ——office_patch 编辑 docx / xlsx / pptx 定点改写后另存新文件；恒写新文件禁覆盖原文件、
  // xlsx setCell 恒转 inlineStr 禁改 sharedStrings 表）；归「文件工作区」卡尾段；
  // 零 preflight（产物为新文件可逆、用户可在管理页删——照 write 族 §8-8 拍板）
  toolRegistry.register({
    name: TOOL_OFFICE_PATCH,
    group: TOOL_GROUP_WORKSPACE,
    title: '编辑 Office 文档',
    desc: OFFICE_PATCH_DESC,
    parametersJson: OFFICE_PATCH_SCHEMA,
    defaultEnabled: false,
    executor: new OfficePatchExecutor()
  });
  // 挂载六件注册块在 ToolMount.ets 自注册（调用位置保持注册序位——toolGroups 成员序与
  // all() 序恒等；六件全 defaultEnabled=false 默认集合解析零漂移；快照与形态约束见该件
  // 末位段注释）
  registerMountTools();
  // 代码工作台两件（执行器在 ToolCodeExec.ets）：exec_code 编写并运行 JavaScript 脚本
  //（沙箱 = 系统自带 JSVM，每次执行新建 VM 执行完销毁）/ exec_output_read 分页读回本会话
  // 临时区文件（超长输出溢出件与脚本 fs.write 产物）；group = TOOL_GROUP_CODE 独立卡，
  // 可用性全权随本卡开关（助手清单进出）；零 preflight（拍板 exec_code 永不设持久免确认——A16）
  toolRegistry.register({
    name: TOOL_EXEC_CODE,
    group: TOOL_GROUP_CODE,
    title: '运行脚本',
    desc: EXEC_CODE_DESC,
    parametersJson: EXEC_CODE_SCHEMA,
    defaultEnabled: false,
    executor: new ExecCodeExecutor()
  });
  toolRegistry.register({
    name: TOOL_EXEC_OUTPUT_READ,
    group: TOOL_GROUP_CODE,
    title: '读取脚本输出',
    desc: EXEC_OUTPUT_READ_DESC,
    parametersJson: EXEC_OUTPUT_READ_SCHEMA,
    defaultEnabled: false,
    executor: new ExecOutputReadExecutor()
  });
  // Python 单件注册块在 ToolPyExec.ets 自注册（调用位置保持注册序位——紧邻脚本工作台族
  // 之后；组序 TOOL_GROUP_PYTHON 亦紧随 TOOL_GROUP_CODE；执行走确认卡〔写档〕、
  // defaultEnabled=false 默认关）
  registerPyTools();
  // Node 单件注册块在 ToolNodeExec.ets 自注册（调用位置保持注册序位——紧随 Python 之后；
  // 组序 TOOL_GROUP_NODE 亦紧随 TOOL_GROUP_PYTHON；执行走确认卡〔写档〕、defaultEnabled=false
  // 默认关；read_output 动作只读不弹卡）
  registerNodeTools();
  // 帮助中心检索（执行器在 ToolHelpSearch.ets）：defaultEnabled=false——用户在「本地检索」
  // 卡显式开（原「仅控制台 seed 启用」语义已随控制台退役废止，现状零变化）
  toolRegistry.register({
    name: TOOL_SEARCH_HELP,
    group: TOOL_GROUP_LOCAL,
    title: '帮助中心检索',
    desc: '检索本应用的帮助中心，用户询问本应用的用法、功能或设置路径时调用。query 越短越好，用功能名或界面上的按钮、菜单名，不要传入整句话。检索不到时先换更短的关键词重试一次。回答必须依据返回条目的内容给出入口路径与操作步骤，仍检索不到才如实说明并指引用户前往 设置 → 更多信息 → 帮助中心 查阅，不要编造界面与操作。',
    parametersJson: '{"type":"object","properties":{"query":{"type":"string",' +
      '"description":"检索关键词。用功能名或界面按钮、菜单名，不要传整句话。"}}, "required":["query"]}',
    defaultEnabled: false,
    executor: new SearchHelpExecutor()
  });
  // 设置查询（执行器在 ToolPref.ets）：无参全量快照 = 遍历白名单现读 AppStorage——白名单
  // setPrefWhitelist 为本件范围单源（演进零双源；原写件 set_app_preference 已随 2026-10-25
  // 退役，2026-11-01 剃刀笔收窄白名单至九项并冻结工具面）；desc 教「问状态先查实不猜测」调用纪律
  toolRegistry.register({
    name: TOOL_GET_APP_PREFERENCE,
    group: TOOL_GROUP_APP, // 应用管理卡（2026-10-25 起普通助手可见可开）
    title: '查询应用设置',
    desc: buildGetPrefDesc(),
    parametersJson: '{"type":"object","properties":{}}',
    defaultEnabled: false,
    executor: new GetAppPreferenceExecutor()
  });
  // 系统提示词编辑（域实现在 ToolPrompts.ets）：set/reset 写向进确认链（档位 = 写操作档）
  toolRegistry.register({
    name: TOOL_EDIT_SYSTEM_PROMPT,
    group: TOOL_GROUP_APP,
    title: '编辑系统提示词',
    desc: buildEditSystemPromptDesc(),
    parametersJson: EDIT_SYSTEM_PROMPT_SCHEMA,
    defaultEnabled: false,
    preflight: editSystemPromptNeedsConfirm,
    executor: new EditSystemPromptExecutor()
  });
  // 会话提示词库管理（同域）：create/update 写向进确认链（写操作档）；删除不开放——跳过
  // UI 确认链不可逆，desc 指引手动删除
  toolRegistry.register({
    name: TOOL_MANAGE_PROMPTS,
    group: TOOL_GROUP_APP,
    title: '管理会话提示词',
    desc: buildManagePromptsDesc(),
    parametersJson: MANAGE_PROMPTS_SCHEMA,
    defaultEnabled: false,
    preflight: managePromptsNeedsConfirm,
    executor: new ManagePromptsExecutor()
  });
  // 功能模型三槽设置（域实现在 ToolFunctional.ets）：set 写向进确认链（写操作档）
  toolRegistry.register({
    name: TOOL_SET_FUNCTIONAL_MODEL,
    group: TOOL_GROUP_APP,
    title: '设置功能模型',
    desc: buildSetFunctionalModelDesc(),
    parametersJson: SET_FUNCTIONAL_MODEL_SCHEMA,
    defaultEnabled: false,
    preflight: setFunctionalModelNeedsConfirm,
    executor: new SetFunctionalModelExecutor()
  });
  // 生成提示词编辑（同域，标题生成/记忆整理/记忆优化/文字识别四槽）：get/set/reset 对齐
  // edit_system_prompt 形制；行名域级「编辑提示词」（未来加槽不再过时）
  toolRegistry.register({
    name: TOOL_EDIT_TITLE_PROMPT,
    group: TOOL_GROUP_APP,
    title: '编辑提示词',
    desc: buildEditTitlePromptDesc(),
    parametersJson: EDIT_TITLE_PROMPT_SCHEMA,
    defaultEnabled: false,
    executor: new EditTitlePromptExecutor()
  });
  // 用量统计查询（域实现在 ToolUsageStats.ets）：只读（三档总览六格 + Token 四格 + 模型
  // 排行 Top10）零写零广播
  toolRegistry.register({
    name: TOOL_GET_USAGE_STATS,
    group: TOOL_GROUP_APP, // 应用管理卡（原独占件卡，2026-10-25 起普通助手可见可开）
    title: '读取用量统计',
    desc: buildGetUsageStatsDesc(),
    parametersJson: GET_USAGE_STATS_SCHEMA,
    defaultEnabled: false,
    executor: new GetUsageStatsExecutor()
  });
  // 记忆检索（执行器在 MemoryGen.ets——记忆域 IO 归口）：★ 模式驱动——读取方式 = 按需读取
  // 且四闸放行时由 ChatSendCtrl 追加（不走 assistants.tools，工具页过滤不出页）；desc =
  // 何时查记忆的唯一引导（能力单源红线——零 system prompt 改动）
  toolRegistry.register({
    name: TOOL_SEARCH_MEMORY,
    modeDriven: true,
    group: TOOL_GROUP_MEMORY,
    title: '检索记忆',
    // 末句反向排除只点**域名不点工具名**（inject 模式下知识库工具可能未声明，点名会诱导
    // 模型调用未声明工具白耗一轮——既有红线，见下方 search_chats 注册块注释）
    desc: '检索用户的长期记忆库。需要了解用户的偏好、背景、身份信息或用户以前交代过的事实时调用。返回按相关度排序的记忆条目。本工具只管关于用户本人的信息。与用户无关的领域知识，例如术语、设定、规范或事物背景，应查知识库。',
    parametersJson: '{"type":"object","properties":{"query":{"type":"string",' +
      '"description":"检索关键词，多个用空格分隔。"}}, "required":["query"]}',
    defaultEnabled: false,
    executor: new SearchMemoryExecutor()
  });
  // 跨会话检索（执行器在 ToolChatSearch.ets）：defaultEnabled=false 常规开关（用户显式开启
  // 才参与）；desc = 唯一引导（能力单源红线）且不点 search_memory 工具名（同上红线）；
  // 隐私三闸见 ToolChatSearch 头注释（敏感跳过 / 隐私会话不声明 / 当前会话中转键排除）
  toolRegistry.register({
    name: TOOL_SEARCH_CHATS,
    group: TOOL_GROUP_LOCAL,
    title: '检索历史会话',
    desc: buildSearchChatsDesc(),
    parametersJson: SEARCH_CHATS_SCHEMA,
    defaultEnabled: false,
    executor: new SearchChatsExecutor()
  });
  // 读取历史会话（同域两工具）：list 最近会话清单 / read 按标题或编号定位读消息原文
  //（conversationId 路 id 优先）；desc 数字自域常量动态拼（禁嵌时变值，RikkaHub #1356 缓存
  // 教训）；外泄防线 = desc 约束句 + 工具卡审计（拍板 4，不加硬守卫）；隐私闸 =
  // isCrossSessionTool 双件同闸（隐私会话两件均不声明）
  toolRegistry.register({
    name: TOOL_GET_CHATS,
    group: TOOL_GROUP_LOCAL,
    title: '读取历史会话',
    desc: buildGetChatsDesc(),
    parametersJson: GET_CHATS_SCHEMA,
    defaultEnabled: false,
    executor: new GetChatsExecutor()
  });
  // 知识库检索（执行器在 ToolKnowledge.ets）：search 按关键词检索 / list 看条目清单；
  // desc 三段式（调用时机/返回形态/划界）在域件、**不点未声明工具的具名**（inject 模式下
  // search_memory 可能未声明，点名诱导白耗一轮——同上红线）；隐私闸 = 无（知识库非会话
  // 内容，不属 isCrossSessionTool，见域件头注释）
  toolRegistry.register({
    name: TOOL_SEARCH_KNOWLEDGE,
    group: TOOL_GROUP_KNOWLEDGE,
    title: '检索知识库',
    desc: buildSearchKnowledgeDesc(),
    parametersJson: SEARCH_KNOWLEDGE_SCHEMA,
    defaultEnabled: false,
    executor: new SearchKnowledgeExecutor()
  });
  // 知识库管理（同域同文件）：七动作（list 两形态 / get 与 read_file 读回 / create_book
  // 建库 / create / update / delete 条目三写）；与上件分工 = 读写分界（检索件只读、本件是
  // 唯一写口）；desc 划界句只点域名不点工具名（同上红线）；隐私闸 = 无（同上）
  toolRegistry.register({
    name: TOOL_MANAGE_KNOWLEDGE,
    group: TOOL_GROUP_KNOWLEDGE,
    title: '管理知识库',
    desc: buildManageKnowledgeDesc(),
    parametersJson: MANAGE_KNOWLEDGE_SCHEMA,
    defaultEnabled: false,
    // delete 进确认链（档位 = 不可逆档——删除条目不可恢复，任何档恒问人）
    preflight: manageKnowledgeNeedsConfirm,
    executor: new ManageKnowledgeExecutor()
  });
  // 记忆管理（执行器在 ToolMemoryManage.ets）：list/create/update/delete 四 action，
  // update/delete 按记忆原文精确匹配定位（纯逻辑在 MemoryText 记忆管理节）；delete 开放
  //（记忆删除无级联确认链，UI 记忆页有完整管理兜底）；管理面独立——记忆总开关/读取方式/
  // memoryInject 均不挂闸（与 UI「停用后仍可查看、编辑和删除」同口径，声明零特判）；
  // 作用域由执行上下文携带（ToolExecutionContext.memoryScopeAssistantId）
  toolRegistry.register({
    name: TOOL_MANAGE_MEMORY,
    group: TOOL_GROUP_MEMORY,
    title: '管理长期记忆',
    desc: buildManageMemoryDesc(),
    parametersJson: MANAGE_MEMORY_SCHEMA,
    defaultEnabled: false,
    // delete 进确认链（档位 = 不可逆档——记忆删除不可恢复，任何档恒问人；list/create/update
    // 照旧直通）
    preflight: manageMemoryNeedsConfirm,
    executor: new ManageMemoryExecutor()
  });
  // 技能加载（执行器在 ToolSkill.ets）：★ 模式驱动第二件——该助手启用了至少一件现存技能时
  // 由 ChatSendCtrl 追加（清单与声明同闸：零启用 = 零注入零声明，工具页过滤不出页）；
  // desc = 何时加载技能的唯一引导（能力单源红线——零 system prompt 改动，与清单头行
  //「先调用 use_skill 加载对应技能正文再作答」互证互补）
  toolRegistry.register({
    name: TOOL_USE_SKILL,
    modeDriven: true,
    group: TOOL_GROUP_SKILL,
    title: '加载技能',
    desc: '加载技能的完整说明书。系统提示词可用技能清单列出每个技能的名称与触发描述，当用户任务与某技能的触发描述匹配时调用本工具，name 逐字取自清单，每次只加载一件。清单为空或无匹配时不得调用。加载后按技能正文执行任务。技能若附带文件，返回内容末尾的 skill_resources 会列出文件名，需要某个文件时再次调用本工具并填 file 参数取用。',
    parametersJson: USE_SKILL_SCHEMA,
    defaultEnabled: false,
    executor: new UseSkillExecutor()
  });
  // 管理技能（与 use_skill 同居 ToolSkill.ets）：非模式驱动——声明由工具页技能管理卡开关
  // 决定，不走 assistants.skills 通道；schema/desc 上限随 SkillText 常量单源动态拼（禁字面
  // 量双源，RikkaHub #1356 缓存教训）；desc 末句「创建成功后告知未启用」= 落库惰性口径
  //（启用仍须用户逐助手手动开）；无 delete——desc 与错误路径指引 设置 → 技能库 手动删
  toolRegistry.register({
    name: TOOL_MANAGE_SKILLS,
    group: TOOL_GROUP_SKILL,
    title: '管理技能',
    desc: buildManageSkillsDesc(),
    parametersJson: MANAGE_SKILLS_SCHEMA,
    defaultEnabled: false,
    executor: new ManageSkillsExecutor()
  });
  // 服务商与模型读取（执行器在 ToolProvider.ets）：只读查询服务商清单/模型清单/当前会话
  // 生效连接；★ 敏感面硬约束——不读密钥与自定义头明文（三敏感列零出现，只回计数与布尔，
  // 断言负向钉）
  toolRegistry.register({
    name: TOOL_GET_PROVIDER_CONFIG,
    group: TOOL_GROUP_APP,
    title: '查询服务商与模型',
    desc: buildGetProviderConfigDesc(),
    parametersJson: GET_PROVIDER_CONFIG_SCHEMA,
    defaultEnabled: false,
    executor: new GetProviderConfigExecutor()
  });
  // 费用估计读取（执行器在 ToolCostStats.ets）：只读查询三档四格/排行/用途分布；四格构造
  // 与费用页同源（UsageStatsCalc.buildCostCells 单源）
  toolRegistry.register({
    name: TOOL_GET_COST_STATS,
    group: TOOL_GROUP_APP,
    title: '读取费用估计',
    desc: buildGetCostStatsDesc(),
    parametersJson: GET_COST_STATS_SCHEMA,
    defaultEnabled: false,
    executor: new GetCostStatsExecutor()
  });
  // ── AI 配置工具域四件（域件分居 ToolProviderAdmin / ToolModelAdmin / ToolProviderProbe）：
  // 全部 defaultEnabled=false 用户显式开（原 console-exclusive + 控制台 seed 语义已随控制台
  // 退役废止）；密钥明文硬边界与确认链分级见各域件头注释 ──
  toolRegistry.register({
    name: TOOL_MANAGE_PROVIDERS,
    group: TOOL_GROUP_APP,
    title: '管理服务商',
    desc: buildManageProvidersDesc(),
    parametersJson: MANAGE_PROVIDERS_SCHEMA,
    defaultEnabled: false,
    // 写档 / 删族不可逆档 / 内置删不弹卡（fail-closed 分阶段）——预检在 ToolProviderAdmin
    preflight: manageProvidersNeedsConfirm,
    executor: new ManageProvidersExecutor()
  });
  toolRegistry.register({
    name: TOOL_MANAGE_MODELS,
    group: TOOL_GROUP_APP,
    title: '管理模型',
    desc: buildManageModelsDesc(),
    parametersJson: MANAGE_MODELS_SCHEMA,
    defaultEnabled: false,
    // remove 不可逆档恒问人，其余写档——预检在 ToolModelAdmin
    preflight: manageModelsNeedsConfirm,
    executor: new ManageModelsExecutor()
  });
  toolRegistry.register({
    name: TOOL_TEST_PROVIDER,
    group: TOOL_GROUP_APP,
    title: '测试服务商连接',
    desc: buildTestProviderDesc(),
    parametersJson: TEST_PROVIDER_SCHEMA,
    defaultEnabled: false,
    // 只读探针零确认（anthropic 支 purpose='test' 最小消耗记账为引擎既有行为）
    executor: new TestProviderExecutor()
  });
  toolRegistry.register({
    name: TOOL_MANAGE_BALANCE,
    group: TOOL_GROUP_APP,
    title: '管理余额查询',
    desc: buildManageBalanceDesc(),
    parametersJson: MANAGE_BALANCE_SCHEMA,
    defaultEnabled: false,
    // 只拦 set（写档）；get / query 只读——预检在 ToolProviderProbe
    preflight: manageBalanceNeedsConfirm,
    executor: new ManageBalanceExecutor()
  });
  hilog.info(DOMAIN, TAG, '内置工具已注册：%{public}d 项', toolRegistry.all().length);
}

// ── 助手启用清单（assistants.tools 列 JSON 串 ⇄ id 数组；DB v14）──
// '' = 未配置 = 默认集合（全部 defaultEnabled 项）；坏 JSON 容错回默认（不炸加载）；
// 未知 id 保留（工具注册表会过滤——删工具后残留 id 无害）
export function parseEnabledToolIds(json: string): string[] {
  const defaults: string[] = defaultEnabledToolIds();
  if (json === '') {
    return defaults;
  }
  let raw: object[] | null = null;
  try {
    const parsed: object = JSON.parse(json);
    raw = Array.isArray(parsed) ? parsed as object[] : null;
  } catch (e) {
    return defaults;
  }
  if (raw === null) {
    return defaults;
  }
  const ids: string[] = [];
  for (const item of raw) {
    if (typeof item === 'string' && item !== '') {
      ids.push(item);
    }
  }
  return ids;
}

// id 数组 → assistants.tools 列 JSON 串（全默认集合 = '' 库列默认形态；空集合 = '[]' 显式全关）
export function serializeEnabledToolIds(ids: string[]): string {
  const defaults: string[] = defaultEnabledToolIds();
  const sameAsDefault: boolean =
    ids.length === defaults.length && ids.every((id: string): boolean => defaults.includes(id));
  if (sameAsDefault) {
    return '';
  }
  return JSON.stringify(ids);
}

function defaultEnabledToolIds(): string[] {
  registerBuiltinTools();
  const ids: string[] = [];
  for (const entry of toolRegistry.all()) {
    if (entry.defaultEnabled) {
      ids.push(entry.name);
    }
  }
  return ids;
}
