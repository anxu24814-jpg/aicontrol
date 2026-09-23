// 工具调用底层（2026-09-02 一期；RikkaHub Tool/GenerationHandler + CubeAgent
// ToolRegistry/ToolExecutionService 调研定稿，裁剪至 aicontrol 形态）：
// · ToolRegistry 单例 = 工具注册表（定义 + 执行器）；内置工具启动注册（幂等）；
// · ToolCallAccumulator = 流式工具调用聚合器（四协议 SseToolDelta 归一增量 → 完整调用，
//   聚合语义对齐 RikkaHub StreamChunkHandler：id/name 分片拼接、args 拼接/全量替换）；
// · ToolRuntime 单例 = 执行域（ask_user 交互桥 + 串行执行入口）；
// · 助手级启用清单解析/序列化（assistants.tools 列，DB v14——'' = 默认集合）。
// 架构（2026-09-08 拆分后）：本文件 = 注册表 + 工具名常量 + 组视图 + 工具卡显示态判定
//   （2026-09-18 卡口径统一：可见卡/可开件/整卡开关——工具页与助手编辑页摘要共用）+
//   启用清单序列化 + 基础内置工具（时间/提问/联网双工具）+ 聚合器 + 执行域；各独立工具域
//   实现分居同目录
//   ToolPrompts / ToolFunctional / ToolUsageStats / ToolPref / ToolHelpSearch / ToolChatSearch
//   / ToolMemoryManage / ToolSkill / ToolProvider / ToolCostStats（本文件只注册）。
// ★ 2026-09-05 控制台助手：内置第 5 工具 search_help（帮助中心本地检索，defaultEnabled=
//   false 不进默认集合——仅控制台助手 seed 显式启用），域实现在 ToolHelpSearch.ets
//   （2026-09-08 外拆），本文件只注册。
// ★ 2026-09-05 设置写工具（同日第二笔）：内置第 6 工具 set_app_preference——按用户明确
//   指令直改应用偏好设置（白名单现值二十键：十五开关 + 五档位。演进：2026-09-06 扩面、
//   09-08 再扩页签动画与启动进入两开关、09-10 扩记忆域与联网搜索域三开关；★ 2026-09-12
//   光感分项退役出表——「悬浮底栏」「其他控件」两档位键删除，两处档位恒跟随总档；
//   ★ 2026-09-13 工具补齐三件扩主动消息四键 + 记忆读取方式至二十键〔该笔漏改本注释，
//   旧文「十五键：十四开关 + 一光感档位」停在 09-12 时点，五百七十三轮自检校正〕。
//   方案 A 直改 + 回执）；defaultEnabled=false 同款不进默认集合——普通助手工具页签照常
//   显示但禁止开启，反向拦截在 AssistantToolsPage）。白名单 map + 参数校验纯函数 + 执行器
//   在 ToolPref.ets（2026-09-08 外拆）；desc/schema 自白名单动态生成零双源。
// ★ 2026-09-06 提示词读写工具域：内置第 7/8 工具 edit_system_prompt（系统提示词
//   get/set/reset）与 manage_prompts（会话提示词库 list/create/update，删除不开放）——
//   域实现全在 ToolPrompts.ets（新增功能域先拆，本文件只注册），defaultEnabled=false +
//   console-exclusive 反向拦截同 set_app_preference。
// ★ 2026-09-06 设置读工具（同日第三笔）：内置工具 get_app_preference——应用偏好设置状态
//   只读查询（CherryStudio diagnose.config 读取面同思路，读写分离两工具——调研档
//   docs/调研-设置状态读取工具-20260906.md；决明拍板只对控制台助手开放且可关闭）。无参
//   全量快照 = 遍历白名单现读 AppStorage（读写同一白名单单源，演进零双源）；实现全在
//   ToolPref.ets（2026-09-08 外拆），本文件只注册，console-exclusive 同族。
// ★ 2026-09-08 功能模型域：内置第 9/10 工具 set_functional_model（默认对话/标题生成模型对
//   查看 + 设置，显示名定位 + 启用口径校验 + 默认槽 tick 广播）与 edit_title_prompt（标题
//   生成提示词 get/set/reset）——域实现全在 ToolFunctional.ets（独立新工具不并入偏好白名单
//   ——四项拍板：独立域文件/两件各司其职/各带 get/不开关闭标题生成），本文件只注册，
//   console-exclusive 同族，seed 升代 V4（九件）。
// ★ 2026-09-08 工具页域分组（决明拍板「按域分，不做模型侧合并」）：ToolEntry.group 必填 +
//   TOOL_GROUP_ORDER 组序 + toolGroups() 分组视图——组行总开关 + 折叠在 AssistantToolsPage，
//   模型面定义零改动（工具名 / desc / schema / seed 全不变，token 账不变）。
// ★ 2026-09-13 语义合并（决明指令「工具开关语义合并——读取类合并、修改类合并，用户层面
//   减少开关，开一个即整类开放」；同日重来笔定稿——「成员行开关保留为高级粒度入口」的
//   首版被否，用户层面只显示组级开关、不能单独控制）：分组轴自「基础能力/设置与配置」域
//   轴改为「读取类/修改类」语义轴——组行开关即语义合并开关（开「修改类」= 底层修改类五件
//   全部进启用清单），成员行只读展示无单行开关（AssistantToolsPage 重来笔）。
//   底层链路零改动：assistants.tools 仍逐件存取、声明仍 defsFor 逐件查、模型面 token 账
//   逐件不变；本文件只管分组元数据。归类 = 只读取信息（时间/提问/联网/帮助/跨会话/设置
//   查询/用量查询）入读取类，改动应用状态（设置直改/系统提示词/提示词库/功能模型/生成
//   提示词）入修改类。
// ★ 2026-09-08 用量统计查询工具（同日第二笔）：内置第 12 工具 get_usage_stats——用量统计页
//   三档（近七天/近三十天/全部）的只读查询（总览六格 + Token 四格 + 模型排行 Top10），域
//   实现在 ToolUsageStats.ets（新增功能域先拆），本文件只注册；defaultEnabled=false +
//   console-exclusive 同族，seed 升代 V6（十件）。
// ★ 2026-09-08 域级最小拆分（一百四十六节，债务条「下次触碰必须拆，不再续期」兑现）：
//   设置读写域 332 行外迁 ToolPref.ets、帮助检索域 157 行外迁 ToolHelpSearch.ets——本文件
//   1200 → 707 总行（剔头 1161 → 659），退出 800 软引导线；两域均为历史「新增功能域先拆」
//   漏网存量（设置读写域 09-05/09-06 直接落本文件），本次按债务条登记候选缝补拆，模型面
//   零改动（工具名 / desc / schema / seed 全不变）。
// ★ 2026-09-13 记忆按需读取（方案-记忆按需读取-20260913）：内置第 13 工具 search_memory
//   ——检索用户长期记忆库（只读；读取方式切「按需读取」时聊天链声明，模型自主调用）。
//   域实现在 MemoryGen.ets（SearchMemoryExecutor）+ MemoryText.ets（检索纯函数），本文件
//   只注册；★ 模式驱动工具族：不走 assistants.tools、不进助手工具页（isModeDriven 判定，
//   MODE_DRIVEN_TOOLS 名单照 CONSOLE_EXCLUSIVE_TOOLS 先例归口本文件）。
// ★ 2026-09-13 跨会话检索（方案-跨会话检索-20260913）：内置第 14 工具 search_chats——
//   跨会话检索其他会话的历史消息（只读；助手工具页常规开关，defaultEnabled=false 不进
//   默认集合）。域实现在 ToolChatSearch.ets（检索纯函数 + SearchChatsExecutor + 当前会话
//   中转键）+ ChatDb.searchMessagesAcross（SQL LIKE 预筛），本文件只注册。隐私闸：locked
//   会话 SQL 层排除 + 敏感消息整条跳过 + 隐私会话不声明（声明层过滤在 ChatSendCtrl）。
// ★ 2026-09-13 记忆管理工具（任务书-记忆管理工具-20260913）：内置第 15 工具
//   manage_memory——list/create/update/delete 四 action 管理长期记忆库（list 按注入顺序
//   编号分页，update/delete 按记忆原文精确匹配定位——纯逻辑在 MemoryText 记忆管理节）。
//   域实现在 ToolMemoryManage.ets（独立工具域先拆，本文件只注册）；MODIFY + console-
//   exclusive 与 manage_prompts 同形并开放 delete（记忆删除无「N 会话引用」级联链）；
//   管理面独立——记忆总开关/读取方式/memoryInject 四闸均不挂本件（声明零特判）。
// ★ 2026-09-13 技能层（方案-技能层-20260913）：内置第 16 工具 use_skill——按系统提示词
//   「可用技能」清单按需加载某件技能的正文（说明书全文）进上下文。域实现在 ToolSkill.ets
//   （独立工具域先拆，本文件只注册）；★ 模式驱动工具族第二件——声明与否由「该助手有没有
//   启用技能」决定（ChatSendCtrl 声明收集处按 assistants.skills ∩ 现存技能非空时追加），
//   不走 assistants.tools、不进助手工具页；defaultEnabled=false 名义值（真值由模式驱动
//   接管）。四层分工里的「技能是怎么做的流程」层，与「工具能做什么」（本注册表）、「提示词
//   是身份与规则」、「记忆是用户的事实」并列。
// ★ 2026-09-13 会话中创建技能（任务书-会话中创建技能-20260913）：内置第 17 工具
//   create_skill——会话中按用户明确意图新建技能（name/description/content 三参直存，
//   重名拒 + 库满转文本回执）。域实现与 use_skill 同居 ToolSkill.ets（两工具同文件先例
//   = ToolPrompts，本文件只注册）；★ 修改类首件非独占——普通助手修改类组开关可开，
//   控制台助手 seed 升代 V7 默认带（AssistantDb）；schema/desc 上限随 SkillText 常量
//   单源动态拼（RikkaHub #1356 缓存教训）。配套元技能 seed 与 builtin 守卫在 SkillDb。
//   ★ 2026-09-16 技能管理工具笔（任务书-技能管理工具与加载枚举-20260916）：create_skill
//   整体退役并入 manage_skills（list/get/create/update 四 action 管理类，无 delete——
//   09-13 缺口盘点 C 档结论维持），修改类非独占与 seed 默认带两项现状原样沿用（seed 升代
//   V9），下方志书条目随形并入。
// ★ 2026-09-13 工具补齐三件（任务书-工具补齐三件-20260913）：内置第 18 工具
//   get_provider_config——服务商与模型配置只读查询（概览 = 服务商清单 + 当前会话生效连接 +
//   全局默认；传 provider = 该家模型清单与价格配置态）。域实现在 ToolProvider.ets（独立工具域
//   先拆，本文件只注册）；★ 敏感面硬约束——不读三列明文（headers/balance_key/
//   balance_headers），只回布尔与计数；双封顶（条数 60 + 字符 4000）防全局 8192 硬切坏 JSON；
//   第 19 工具 get_cost_stats——费用估计只读查询（三档四格 + 模型排行 + 用途分布），域实现在
//   ToolCostStats.ets；四格构造与费用页同源（UsageStatsCalc.buildCostCells 单源——页面私有
//   方法本笔外迁）。两件均 defaultEnabled=false + console-exclusive（配置读面照旧只对控制台
//   开），控制台 seed 升代 V8 默认带（AssistantDb）。
// ★ 2026-09-18 工具页分类卡重组（决明「工具太多独占通用混杂——类似工具合为一个卡，只留
//   一个新的主副标题，不要留下多项」）：分组轴自「读取类/修改类」语义轴改为功能卡轴八卡
//   ——基础能力（时间/提问）+ 联网搜索（联网五件）+ HTTP 请求（http_request）+
//   记忆（search_memory/manage_memory）+ 知识库（search_knowledge）+ 本地检索（帮助/
//   跨会话两件）+ 技能管理（use_skill/manage_skills）+ 应用管理（独占九件全收一卡，普通
//   助手整卡受限）；页面只渲染卡（一卡一枚开关 + 新主副标题，无成员明细无展开），成员行/
//   组头行/折叠机制退役。底层链路零改动：assistants.tools 仍逐件存取、defsFor 仍逐件声明、
//   模型面 token 账逐件不变，本文件只改分组元数据。★ uiDesc 随成员行退役整字段删除（页面
//   不再渲染逐件副标题；请求侧 desc 不受影响）。
//   ★ 2026-09-21 记忆与知识库剥离笔（任务书-工具页卡片重组与记忆开放-20260921）：自「本地
//   检索」卡剥出两张新卡——记忆（search_memory 模式件 + manage_memory）、知识库
//   （search_knowledge），同为「给模型的知识面」故组序插在本地检索之前；连同 manage_memory
//   自 CONSOLE_EXCLUSIVE_TOOLS 移出（普通助手可开——决策 13）。独占件随之十件 → 九件，
//   应用管理卡判据「独占件只出现在应用管理卡」原样成立（记忆卡零独占件）。
// ★ 2026-09-20 HTTP 请求独立域笔（决明指令「http 请求工具从联网工具内拆分成独立的，设置页
//   工具页显示，可控制权限授予之类」→ 拍板甲档「真独立」+ 写方法确认档）：http_request 自
//   联网搜索卡移出、单列 TOOL_GROUP_HTTP 卡（组序置联网搜索之后）——同步移出
//   WEB_DOMAIN_TOOLS（不再随联网搜索三级闸门：总开关 / 会话「联网」开关 / 助手清单含
//   search_web 三源均不再约束本件）；ToolHttp 执行器首行联网总开关守底行随域归属移除；
//   用户可见控制面 = 助手工具页「HTTP 请求」卡开关（启用）+ 设置 → 工具调用页「HTTP 写操作
//   确认」卡（每次确认 / 自动通过两档，键 prefHttpWriteAutoApprove）。模型面（工具名 / seed）
//   零改动；desc 与 schema 只把写确认句按默认档限定（★ 2026-09-20 同笔随修，理由见
//   ToolHttp 头注释「模型面写确认句」条）。
// 边界：协议方言（tools 注入与工具消息翻译）在 RequestCompose；流式解析在 SseParser；
// 多轮循环编排在 ChatSendCtrl——本文件只管「工具是什么、怎么聚合、怎么执行」。

import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConfirmPrompt, ToolExecutor } from './ToolContracts';
import { AiToolCall, AiToolDef } from './AiTypes';
import { SseToolDelta } from './SseParser';
import { isSearchServiceEnabled } from '../AppPreferences';
import { WebFetchOutcome, WebSearchOutcome, fetchUrlContent } from './WebSearch';
import { dispatchSearch } from '../search/SearchEngineRegistry';
import { cleanSearchQuery, normalizeRelativeTime } from '../search/SearchQueryClean';
import { SearchHelpExecutor } from './ToolHelpSearch';
import { GetAppPreferenceExecutor, SetAppPreferenceExecutor, buildGetPrefDesc, buildSetPrefDesc,
  buildSetPrefSchema } from './ToolPref';
import { EditSystemPromptExecutor, ManagePromptsExecutor, EDIT_SYSTEM_PROMPT_SCHEMA,
  MANAGE_PROMPTS_SCHEMA, buildEditSystemPromptDesc, buildManagePromptsDesc } from './ToolPrompts';
import { EditTitlePromptExecutor, SetFunctionalModelExecutor, EDIT_TITLE_PROMPT_SCHEMA,
  SET_FUNCTIONAL_MODEL_SCHEMA, buildEditTitlePromptDesc, buildSetFunctionalModelDesc } from './ToolFunctional';
import { GetUsageStatsExecutor, GET_USAGE_STATS_SCHEMA,
  buildGetUsageStatsDesc } from './ToolUsageStats';
import { SearchMemoryExecutor } from '../MemoryGen';
import { SearchChatsExecutor, GetChatsExecutor, GET_CHATS_SCHEMA,
  buildGetChatsDesc } from './ToolChatSearch';
import { ManageMemoryExecutor, MANAGE_MEMORY_SCHEMA,
  buildManageMemoryDesc } from './ToolMemoryManage';
import { SearchKnowledgeExecutor, SEARCH_KNOWLEDGE_SCHEMA, buildSearchKnowledgeDesc,
  ManageKnowledgeExecutor, MANAGE_KNOWLEDGE_SCHEMA,
  buildManageKnowledgeDesc } from './ToolKnowledge';
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
import { HttpRequestExecutor, HTTP_REQUEST_DESC, HTTP_REQUEST_SCHEMA,
  httpRequestNeedsConfirm } from './ToolHttp';

const DOMAIN: number = 0x0001;
const TAG: string = 'ToolTypes';

// ── 内置工具名常量（函数名 = 请求侧 name，全工程禁裸字符串）──
export const TOOL_GET_TIME_INFO: string = 'get_time_info';
export const TOOL_ASK_USER: string = 'ask_user';
export const TOOL_SEARCH_WEB: string = 'search_web';
export const TOOL_SCRAPE_WEB: string = 'scrape_web';
// 内置浏览器三工具（2026-09-16 P1 双件 + 2026-09-18 P2 动作件，读域在 ToolBrowse.ets /
// 动作域在 ToolBrowseAct.ets〔2026-09-18 修复笔自 ToolBrowse 拆出〕——常量在此归口）：
// browse_open 后台打开网页读渲染后正文 / browse_read 续读或取可交互元素或诊断信号 /
// browse_act 对当前页执行 scroll·click·type·select·press_key 动作；隐形宿主在
// common/BrowseWeb.ets，声明层过滤与助手页压制走下方 WEB_DOMAIN_TOOLS 单源
export const TOOL_BROWSE_OPEN: string = 'browse_open';
export const TOOL_BROWSE_READ: string = 'browse_read';
export const TOOL_BROWSE_ACT: string = 'browse_act';
// HTTP 请求工具（2026-09-19 任务书-HTTP请求工具-20260919 执行笔；实现在 ToolHttp.ets——
// 常量在此归口）：通用 HTTP 工具（method + URL + headers + body），写方法逐次确认
//（preflight 弹确认卡，设置页可切「自动通过」——2026-09-20 确认档笔）、GET/HEAD/OPTIONS
// 直通；defaultEnabled=false 不进默认集合（true = 静默向存量助手发放写能力，不可接受）；
// ★ 2026-09-20 HTTP 请求独立域笔：自联网搜索卡移出、单列 TOOL_GROUP_HTTP 卡——启用面
// 只由助手工具页本卡开关决定，不再随联网搜索（已移出 WEB_DOMAIN_TOOLS，无联网三级闸门）
export const TOOL_HTTP_REQUEST: string = 'http_request';
export const TOOL_SEARCH_HELP: string = 'search_help';
export const TOOL_SET_APP_PREFERENCE: string = 'set_app_preference';
export const TOOL_GET_APP_PREFERENCE: string = 'get_app_preference';
// 提示词读写域两工具（实现在 ToolPrompts.ets——常量在此归口，注册/拦截/seed 同源引用）
export const TOOL_EDIT_SYSTEM_PROMPT: string = 'edit_system_prompt';
export const TOOL_MANAGE_PROMPTS: string = 'manage_prompts';
// 功能模型域两工具（实现在 ToolFunctional.ets——常量在此归口，注册/拦截/seed 同源引用）
export const TOOL_SET_FUNCTIONAL_MODEL: string = 'set_functional_model';
export const TOOL_EDIT_TITLE_PROMPT: string = 'edit_title_prompt';
// 用量统计查询工具（实现在 ToolUsageStats.ets——常量在此归口，注册/拦截/seed 同源引用）
export const TOOL_GET_USAGE_STATS: string = 'get_usage_stats';
// 记忆检索工具（实现在 MemoryGen.ets——常量在此归口；2026-09-13 记忆按需读取笔）：
// 模式驱动工具——声明与否由记忆页「读取方式」决定（ChatSendCtrl 追加），不走
// assistants.tools 启用清单，也不进助手工具页（MODE_DRIVEN_TOOLS 过滤）
export const TOOL_SEARCH_MEMORY: string = 'search_memory';
// 跨会话检索工具（实现在 ToolChatSearch.ets——常量在此归口；2026-09-13 跨会话检索笔）：
// 常规工具——助手工具页开关（assistants.tools 列），defaultEnabled=false 不进默认集合；
// 隐私会话不声明（ChatSendCtrl 声明层过滤，与记忆工具隐私闸同源）
export const TOOL_SEARCH_CHATS: string = 'search_chats';
// 跨会话读取工具（实现在 ToolChatSearch.ets——常量在此归口；2026-09-19 跨会话记忆深化笔，
// BLOCKED #10 落地）：get_chats 两动作（list 最近会话清单 / read 按标题通读指定会话消息
// 原文）——常规工具（助手工具页本地检索卡开关），defaultEnabled=false 不进默认集合不入
// seed；与 search_chats 同属跨会话读取域，隐私会话经 isCrossSessionTool 双件同闸不声明
export const TOOL_GET_CHATS: string = 'get_chats';
// 知识库检索工具（实现在 ToolKnowledge.ets——常量在此归口；2026-09-21 世界书知识库首版
// 笔，任务书-世界书知识库-20260921；用户可见名「知识库」）：常规工具（助手工具页「知识库」
// 卡开关〔2026-09-21 剥离笔自「本地检索」卡移出成卡〕，assistants.tools 通道），
// defaultEnabled=false 不进任何默认集合；**只读**——search / list 两动作，无写动作。
// ★ 2026-09-21 知识库第二笔下本修订：原「无 manage_knowledge / 用户手写是定义边界」两句已随
// 本笔作废（写入口已开，见下条）；此件保持只读不动，「用户手写」边界改按「来源 + 内容」两条
// 并写（口径见 ToolKnowledge.ets 头注释）。「工具操作面 ⊆ UI 操作面」仍成立：管理工具的各动作在
// UI 都有对应入口（书级改名与删库只有 UI 有，工具侧没有）；隐私会话照常声明（知识库非会话内容，
// 不进 isCrossSessionTool 名单——理由见域件头注释）
export const TOOL_SEARCH_KNOWLEDGE: string = 'search_knowledge';
// 知识库管理工具（实现在 ToolKnowledge.ets 同文件——常量在此归口；2026-09-21 知识库第二笔
// 下本，任务书-知识库写入口与上限放宽-20260921）：**知识库唯一写口**——七动作 list / get /
// read_file / create_book / create / update / delete（其中 get 与 read_file 为只读读回；
// 写动作 = create_book / create / update / delete，条目级三写全开含 delete；**书级只开放建库**，
// 改名与删库留给设置页）。常规工具（助手工具页「知识库」卡开关，assistants.tools 通道），
// defaultEnabled=false 不进任何默认集合、不入 seed（非立身能力，用户显式开）；写入恒带
// source='assistant'（UI 编辑页恒 'user'）。定位范围 = **全部书，不取助手启用集**（与
// search_knowledge 的启用集作用域刻意不同：新建的库默认不被任何助手启用，卡启用集会让助手刚
// 建的库写不进去——闸与建议之别见域件头注释）；隐私会话照常声明（同上）
export const TOOL_MANAGE_KNOWLEDGE: string = 'manage_knowledge';
// 记忆管理工具（实现在 ToolMemoryManage.ets——常量在此归口；2026-09-13 记忆管理工具笔）：
// ★ 2026-09-21 剥离笔起为**非独占件**（原 console-exclusive 修改件，与 manage_prompts
// 同形并开 delete——「归修改类」语义轴已于 2026-09-18 分类卡重组退役，「同形」类比亦弱：
// 独占九件里唯它是内容面，最接近的 use_skill/manage_skills 两件都非独占；决明 2026-09-21
// 拍板乙案），普通助手经「记忆」卡开关可开；助手工具页常规开关（defaultEnabled=false 不进
// 默认集合，控制台助手经 seed 默认开）。
// ★ 作用域（决策 13 已知后果，勿"顺手修"）：执行器选库由 ChatSendCtrl 现写的
// MEMORY_EXEC_ASSISTANT_KEY 决定——助手「记忆作用域」= 助手记忆时锁该助手自己的库，留在
// 默认「全局记忆」时锁**全局库**（改的会影响所有用全局记忆的助手，这是拍板接受的取舍；
// 用户要隔离就去助手记忆页切作用域）。禁加确认门、禁加作用域闸、禁改 memoryScope 默认值
export const TOOL_MANAGE_MEMORY: string = 'manage_memory';
// 技能加载工具（实现在 ToolSkill.ets——常量在此归口；2026-09-13 技能层笔 1）：模式驱动
// 工具第二件——声明与否由「该助手是否启用了技能」决定（ChatSendCtrl 追加），不走
// assistants.tools 启用清单，也不进助手工具页（MODE_DRIVEN_TOOLS 过滤）
export const TOOL_USE_SKILL: string = 'use_skill';
// 管理技能工具（实现在 ToolSkill.ets——常量在此归口；2026-09-16 技能管理工具笔，
// create_skill 整体退役并入本件）：技能管理卡**非独占**件——普通助手工具页技能管理卡开关
// 可开（非独占现状沿用），控制台助手 seed 默认开；list/get/create/update 四 action 无
// delete（删除不可逆且绕过 UI 确认链，desc 指引 设置 → 技能库 手动删，manage_prompts 先例）
export const TOOL_MANAGE_SKILLS: string = 'manage_skills';
// 服务商与模型读取（实现在 ToolProvider.ets——常量在此归口；2026-09-13 工具补齐三件笔）：
// console-exclusive 读取件（与 get_usage_stats 同形），只读查询服务商清单/模型清单/当前
// 会话生效连接；★ 不读密钥与自定义头明文（三敏感列零出现，断言负向钉）
export const TOOL_GET_PROVIDER_CONFIG: string = 'get_provider_config';
// 费用估计读取（实现在 ToolCostStats.ets——常量在此归口；2026-09-13 工具补齐三件笔）：
// console-exclusive 读取件（与 get_usage_stats 同形），只读查询费用估计页三档的四格/
// 排行/用途分布；四格构造与费用页同源（UsageStatsCalc.buildCostCells 单源）
export const TOOL_GET_COST_STATS: string = 'get_cost_stats';

// 仅控制台助手可启用的工具（设置读写域 + 提示词读写域 + 功能模型域 + 用量统计查询 +
// 服务商与费用两读件——直改设置/查询设置状态/系统提示词/提示词库/功能模型对/
// 标题提示词/用量数据/服务商与模型配置/费用估计；★ 2026-09-21 剥离笔起 manage_memory
// 移出本名单——记忆属内容面（改的是用户的事实，非应用配置），普通助手可开；反向拦截在
// AssistantToolsPage 组批量路径（toggleGroup——2026-09-13 重来笔起单行开关已删），
// seed 层在 AssistantDb。加新 console-exclusive 工具在此
// 追加一行，拦截与断言自动跟随）
const CONSOLE_EXCLUSIVE_TOOLS: string[] = [TOOL_SET_APP_PREFERENCE,
  TOOL_GET_APP_PREFERENCE, TOOL_EDIT_SYSTEM_PROMPT, TOOL_MANAGE_PROMPTS,
  TOOL_SET_FUNCTIONAL_MODEL, TOOL_EDIT_TITLE_PROMPT, TOOL_GET_USAGE_STATS,
  TOOL_GET_PROVIDER_CONFIG, TOOL_GET_COST_STATS];

export function isConsoleExclusive(name: string): boolean {
  return CONSOLE_EXCLUSIVE_TOOLS.includes(name);
}

// 模式驱动工具（声明与否由全局模式开关决定，不走 assistants.tools 启用清单）——2026-09-13
// 记忆按需读取笔立表，同日技能层笔入第二件：search_memory（读取方式切「按需读取」且四闸
// 放行时由 ChatSendCtrl 声明收集处追加）+ use_skill（该助手启用了至少一件现存技能时追加）。
// 工具页（AssistantToolsPage 渲染源 toolGroups()）按本名单过滤不出页——「模式开关 × 工具页
// 开关」双重控制会打架（模式关时页上开了也不生效、模式开时页上没开也照常声明，两处真相互
// 相矛盾）。加新模式驱动工具在此追加一行，页面过滤与发送链剔除自动跟随（常量归口照
// CONSOLE_EXCLUSIVE_TOOLS 先例）
const MODE_DRIVEN_TOOLS: string[] = [TOOL_SEARCH_MEMORY, TOOL_USE_SKILL];

export function isModeDriven(name: string): boolean {
  return MODE_DRIVEN_TOOLS.includes(name);
}

// 联网域工具名单源（2026-09-16 内置浏览器 P1 立 / 2026-09-18 P2 扩五件 / ★ 2026-09-20
// HTTP 请求独立域笔：http_request 移出本名单，自成一域 TOOL_GROUP_HTTP〔见下方注册块〕）：
// 随联网域可用性（助手清单 ∩ 会话开关 ∩ 总开关，ChatSendCtrl.webDomainAllowed）同进同出。
// ★ 口径（防未来第二处各写一套）：**声明层全剔五件**（ChatSendCtrl 过滤表达式）；**UI 压制
// 剔从属四件** = isWebDomainTool(name) && name !== TOOL_SEARCH_WEB
//（AssistantToolsPage.isToolSuppressed）——search_web 是域主件（它本身就是那个开关），
// 不做自压制。未来新增联网域工具只改本清单一处。
const WEB_DOMAIN_TOOLS: string[] = [TOOL_SEARCH_WEB, TOOL_SCRAPE_WEB, TOOL_BROWSE_OPEN,
  TOOL_BROWSE_READ, TOOL_BROWSE_ACT];

export function isWebDomainTool(name: string): boolean {
  return WEB_DOMAIN_TOOLS.includes(name);
}

// 搜索类工具结果统一 JSON 载荷（Cube SearchResultOutput 同构——results[].index 供引文卡
// 编号与模型引用对齐，id 供引擎侧去重/对齐；执行结果 role='tool' 行即此串，引文卡回放
// 时按工具名二次解析）
export interface SearchResultItemPayload {
  index: number;
  id: string;
  title: string;
  url: string;
  snippet: string;
}

interface SearchResultOutputPayload {
  query: string;
  searchEngine: string;
  results: SearchResultItemPayload[];
  summary: string;
}

// 工具执行器契约 ToolExecutor 已外迁叶子模块 ToolContracts.ets（2026-09-13 真机闪退修复笔
// ——本文件是工具域聚合根，域再反向引它即成环；环内模块作用域读写对方绑定会踩未初始化绑定，
// 详见该文件头注释）。本文件按需从那里引，且**不再对外转出**（转出会把环接回来）。

// 注册条目（定义 + 展示 + 执行器三合一）
export interface ToolEntry {
  name: string;
  title: string; // UI 展示名（截图口径：「获取当前时间」「向用户提问」）
  desc: string; // 请求侧 description（模型阅读——引用规范等工具细节全在此，英文原文不动）
  // 工具页分组（功能卡轴——TOOL_GROUP_* 八常量，2026-09-08 分组显示 / 2026-09-13 语义轴 /
  // 2026-09-18 分类卡轴）：必填字段 = 新增工具忘标分组时编译期报错（比映射表少一个静默漂移面）
  group: string;
  parametersJson: string; // JSON Schema 原串（compose 内 parse 后入请求体）
  defaultEnabled: boolean; // 默认启用（ assistants.tools 列为空时的默认集合成员）
  executor: ToolExecutor;
  // 确认链预检（2026-09-19 HTTP 请求工具笔，确认链注册表化泛化）：返回 null = 直通，非 null
  // = 需弹确认卡（text 即卡面主因句，level 即档位）——工具轮 executeToolCalls 预检循环按此
  // 收集（browse_act 异步精判 / http_request 同步 async，统一走 await）；缺省 = 无确认环节。
  // ★ 2026-09-20 审批卡视觉迁移笔 A：形态由「返回串（'' = 直通）」改「说明串＋档位二元组」
  //（ConfirmPrompt，落叶子 ToolContracts——域件要消费它，落聚合根会接回环，见该文件头注释）。
  // ★ 实现契约（2026-09-19 自检 P3-5）：实现必须全包 try/catch，任何异常一律返 null——预检
  // 循环裸 await 无兜底，实现抛错 = 整轮静默死、发送态永挂（现役两件均自防）。编排层不代
  // 兜：抛错兜成 null 会把「预检异常」翻译成「直通执行」，对依赖预检弹卡护写动作的工具 =
  // 绕过确认红线，比静默死更危险——契约落本注释位（后来者必读），自防责任在实现侧
  preflight?: (argsJson: string) => Promise<ConfirmPrompt | null>;
  // 用户允许后、执行前的授予动作（2026-09-19）：目前唯一持有者 browse_act（写单次批准戳）
  // ——函数体零改动，接线方式自编排层硬编码改注册表分发；http_request 不带（跨工具写戳 =
  // 语义污染 + 未来第三件带戳工具的误消费口子）
  onApproved?: (convId: string) => void;
}

// ── 注册表单例 ──
export class ToolRegistry {
  private entries: Map<string, ToolEntry> = new Map<string, ToolEntry>();

  register(entry: ToolEntry): void {
    this.entries.set(entry.name, entry);
  }

  get(name: string): ToolEntry | undefined {
    return this.entries.get(name);
  }

  // 全量条目（工具页签 UI 渲染源；注册序 = 数组序稳定）
  all(): ToolEntry[] {
    const list: ToolEntry[] = [];
    this.entries.forEach((entry: ToolEntry): void => {
      list.push(entry);
    });
    return list;
  }

  // 启用清单 → 请求侧声明（ChatSendCtrl 发送前消费；未知 id 过滤——脏数据防御）
  defsFor(enabledIds: string[]): AiToolDef[] {
    const defs: AiToolDef[] = [];
    for (const id of enabledIds) {
      const entry: ToolEntry | undefined = this.entries.get(id);
      if (entry !== undefined) {
        defs.push({ name: entry.name, description: entry.desc,
          parametersJson: entry.parametersJson });
      }
    }
    return defs;
  }
}

// 全局注册表单例（进程级；内置工具首用注册幂等——registerBuiltinTools 守卫）
export const toolRegistry: ToolRegistry = new ToolRegistry();
let builtinRegistered: boolean = false;

// 函数名 → 展示名（工具卡标题用；未注册函数名原样返回——未知/自定义工具可读性兜底）
export function toolTitle(name: string): string {
  registerBuiltinTools();
  const entry: ToolEntry | undefined = toolRegistry.get(name);
  return entry !== undefined ? entry.title : name;
}

// ── 工具页分组（2026-09-08 决明拍板分组显示；2026-09-13 语义轴两笔；★ 2026-09-18 分类卡
//   重组——本文件管分组元数据与卡显示态判定〔可见卡/可开件/整卡开关〕，卡面副标题与图标
//   在 AssistantToolsPage）──

// 组标题（功能卡轴唯一来源，2026-09-18 分类卡重组笔：同类工具合一张卡，一卡一枚开关；
// 独占件全收「应用管理」卡——普通助手整卡受限，独占与通用不再混排；★ 2026-09-20 HTTP
// 请求独立域笔：http_request 自联网搜索卡移出、单列「HTTP 请求」卡——不再随联网搜索可用性，
// 与搜索能力各自独立开关；★ 2026-09-21 记忆与知识库剥离笔：记忆与知识库自「本地检索」卡
// 剥出各成一卡——两者与本地检索同为「给模型的知识面」，故组序插在本地检索之前
//〔同构件分卡的由来：记忆检索/会话检索/帮助检索/知识库检索四类同塞一卡，模型划界与用户
// 理解都容易出错〕；组序 = TOOL_GROUP_ORDER，页面按此渲染）
export const TOOL_GROUP_BASIC: string = '基础能力';
export const TOOL_GROUP_WEB: string = '联网搜索';
export const TOOL_GROUP_HTTP: string = 'HTTP 请求';
export const TOOL_GROUP_MEMORY: string = '记忆';
export const TOOL_GROUP_KNOWLEDGE: string = '知识库';
export const TOOL_GROUP_LOCAL: string = '本地检索';
export const TOOL_GROUP_SKILL: string = '技能管理';
export const TOOL_GROUP_APP: string = '应用管理';
const TOOL_GROUP_ORDER: string[] = [TOOL_GROUP_BASIC, TOOL_GROUP_WEB, TOOL_GROUP_HTTP,
  TOOL_GROUP_MEMORY, TOOL_GROUP_KNOWLEDGE, TOOL_GROUP_LOCAL, TOOL_GROUP_SKILL, TOOL_GROUP_APP];

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

// ── 工具卡显示态（★ 2026-09-18 卡口径统一：工具页卡开关与助手编辑页卡面摘要**同源**）──
// 背景：工具页分类卡重组后用户可见入口 = 一组卡（一卡一枚开关；★ 2026-09-21 记忆与知识库
// 剥离笔后为八张），而助手编辑页「工具调用」卡面摘要仍按底层逐件 id 计数（'联网开 · 12 项
// 启用'）——两处口径不一：用户点进去只看到几个开关，摘要却报十几个。故摘要改报「已开卡数 /
// 卡总数」，本段即「卡是否已开」的**唯一判定源**（AssistantToolsPage 卡开关显示态 +
// AssistantEditPage 卡面摘要同调此处，禁各自另写一套——规范 §4.2 放行逻辑单源）。语义与
// 页面显示逐条对齐：
// ① 可见卡 = 八组轴按 TOOL_GROUP_ORDER，模式驱动件（isModeDriven）成员与卡两级同滤、卡内
//    滤空则整卡不出现（现役八卡恒出现——记忆卡可见成员恰 manage_memory 一件）；
// ② 卡内**可开件**（分母）= 剔除 console-exclusive（非控制台助手不可开）与联网压制件
//   （从属四件在「清单不含联网搜索」或「联网搜索总开关关闭」时不可用）后的成员——被排除件
//    若进分母，普通助手的应用管理卡与总开关关闭时的联网卡都会永不全开（用户点开仍显示关）；
// ③ 卡开关显示态 = 可开件非空且**全开**；④ 卡面摘要计数 = 可见卡中已开张数。

// 工具页可见卡（模式驱动件过滤——卡视图唯一入口；原 AssistantToolsPage.loadVisibleGroups
// 上迁本文件，两页共用）
export function visibleToolGroups(): ToolGroup[] {
  registerBuiltinTools();
  const visible: ToolGroup[] = [];
  for (const group of toolGroups()) {
    const members: ToolEntry[] = group.members.filter((m: ToolEntry): boolean =>
      !isModeDriven(m.name));
    if (members.length > 0) {
      visible.push({ title: group.title, members: members });
    }
  }
  return visible;
}

// 联网域从属件压制判定（纯函数形：总开关态与候选集合入参——页面显示态与摘要计数同用）：
// 联网域从属件（isWebDomainTool 且非 search_web 本体）在「候选集合不含联网搜索」或「联网
// 搜索总开关关闭」时整体不可用；search_web 是那个开关本身，不做自压制（判据单源 = 本函数，
// 页面 isToolSuppressed 只补默认形参与 @StorageProp 取值）
export function isToolSuppressedInList(name: string, candidateIds: string[],
  webServiceEnabled: boolean): boolean {
  if (!isWebDomainTool(name) || name === TOOL_SEARCH_WEB) {
    return false;
  }
  return !candidateIds.includes(TOOL_SEARCH_WEB) || !webServiceEnabled;
}

// 逐件可开（console-exclusive 反向拦截 + 压制两因合一——卡内可开件与摘要计数共同判据）
function isToolEnablable(name: string, candidateIds: string[], isConsoleAssistant: boolean,
  webServiceEnabled: boolean): boolean {
  if (isConsoleExclusive(name) && !isConsoleAssistant) {
    return false;
  }
  return !isToolSuppressedInList(name, candidateIds, webServiceEnabled);
}

// 卡内可开件（卡开关显示态与受限标注的分母；求值一律传「候选集合」——卡批量开时传批后
// 目标集合，压制判定依赖候选集合是否含联网搜索）
export function enablableToolMembers(group: ToolGroup, candidateIds: string[],
  isConsoleAssistant: boolean, webServiceEnabled: boolean): ToolEntry[] {
  return group.members.filter((m: ToolEntry): boolean =>
    isToolEnablable(m.name, candidateIds, isConsoleAssistant, webServiceEnabled));
}

// 卡开关显示态 = 可开件非空且全开（可开件 0 = 恒关——普通助手的应用管理整卡不可开）
export function toolGroupAllOn(group: ToolGroup, candidateIds: string[],
  isConsoleAssistant: boolean, webServiceEnabled: boolean): boolean {
  const enablable: ToolEntry[] = enablableToolMembers(group, candidateIds,
    isConsoleAssistant, webServiceEnabled);
  return enablable.length > 0 && enablable.every((m: ToolEntry): boolean =>
    candidateIds.includes(m.name));
}

// ── 内置工具执行器 ──

// 获取当前时间（RikkaHub TimeInfoTool / CubeAgent GetTimeInfoExecutor 同口径字段裁剪）：
// 本地日期/星期/时间/时区/时间戳。无参数工具（schema 空 object——防 provider 校验空参缺 type）
class GetTimeInfoExecutor implements ToolExecutor {
  execute(_argsJson: string): Promise<string> {
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
  execute(_argsJson: string): Promise<string> {
    return Promise.resolve(JSON.stringify({ error: 'ask_user 应走交互桥，占位执行器不可达' }));
  }
}

// ask_user 入参 schema（rawSchema 原串注入——ArkTS 禁无类型对象字面量，CubeAgent 同款姿势；
// 多问上限 5 与 UI 卡一致〔2026-09-22 八百七十三节 3 → 5，对齐「方案访谈」正文的「三到五个
// 为限」〕；★ 笔 B 补选项两字段——options 上限 4 与卡面 ASK_OPTIONS_MAX 同源）
const ASK_USER_SCHEMA: string = '{"type":"object","properties":{"questions":{"type":"array",' +
  '"minItems":1,"maxItems":5,"items":{"type":"object","properties":{' +
  '"id":{"type":"string","description":"问题唯一短 id"},"question":{"type":"string",' +
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
  toolRegistry.register({
    name: TOOL_ASK_USER,
    group: TOOL_GROUP_BASIC,
    title: '向用户提问',
    desc: '模型需要澄清时向你发起的提问，你的答复会作为工具结果回给模型继续生成。能给选项时请给选项，用户也可以自己写。',
    parametersJson: ASK_USER_SCHEMA,
    defaultEnabled: true,
    executor: new AskUserPlaceholderExecutor()
  });
  // 联网搜索双工具（2026-09-03 第三批①，Cube BuiltinTools 声明裁剪——schema 原串
  // 直注；description 含引用规范原文 = Cube 分工原则「工具细节全在 description，
  // 系统提示词只留通用规则」）
  toolRegistry.register({
    name: TOOL_SEARCH_WEB,
    group: TOOL_GROUP_WEB,
    title: '联网搜索',
    desc: 'Search the web for up-to-date, specific, or verifiable information. First decide whether web access is truly needed; use your own knowledge for common stable facts and pure generation tasks. Each search has real cost, so generate focused keywords and run multiple searches only when more evidence is needed. Cite used sources as standard Markdown links like [title](url), not bare [1] or [2] numbers. Zero results or a missing-key error is final: do not repeat the same query; for key errors, tell the user to configure the engine in Settings.',
    parametersJson: '{"type":"object","properties":{"query":{"type":"string",' +
      '"description":"聚焦搜索关键词。用于搜索外部实时、特定或需要验证的信息，不要传入整段用户问题。"}}, "required":["query"]}',
    defaultEnabled: true,
    executor: new SearchWebExecutor()
  });
  toolRegistry.register({
    name: TOOL_SCRAPE_WEB,
    group: TOOL_GROUP_WEB,
    title: '读取网页',
    desc: 'Scrape a URL for detailed page content. Use this when the user provides a specific URL, asks to read or summarize a page, or search snippets are insufficient. Avoid using it for common questions unless the user asks.',
    parametersJson: '{"type":"object","properties":{"url":{"type":"string",' +
      '"description":"要读取的网页 URL。用户给出 URL 或要求总结、分析某个网页时，原样传入 URL。"}}, "required":["url"]}',
    defaultEnabled: true,
    executor: new ScrapeWebExecutor()
  });
  // 内置浏览器双工具（2026-09-16 内置浏览器 P1，任务书-内置浏览器P1-20260916；执行器在
  // ToolBrowse.ets——独立工具域先拆，本文件只注册）：browse_open 后台隐形 Web 打开网页读
  // 渲染后正文（ArkWeb AI 页面命令 getLiteDom，API 26），browse_read 续读正文或取可交互
  // 元素清单；联网搜索卡、默认开（拍板「跟现有联网工具一致」），随联网域三级闸门同进同出
  //（声明层过滤 isWebDomainTool / 执行器首行 isSearchServiceEnabled 兜底）；隐私会话走
  // Web 隐私模式分轨（宿主 BrowseWeb.BrowseHost 随 ChatPage 挂载）
  toolRegistry.register({
    name: TOOL_BROWSE_OPEN,
    group: TOOL_GROUP_WEB,
    title: '打开网页',
    desc: BROWSE_OPEN_DESC,
    parametersJson: BROWSE_OPEN_SCHEMA,
    defaultEnabled: true,
    executor: new BrowseOpenExecutor()
  });
  toolRegistry.register({
    name: TOOL_BROWSE_READ,
    group: TOOL_GROUP_WEB,
    title: '浏览当前页',
    desc: BROWSE_READ_DESC,
    parametersJson: BROWSE_READ_SCHEMA,
    defaultEnabled: true,
    executor: new BrowseReadExecutor()
  });
  // 操作网页（2026-09-18 内置浏览器 P2，任务书-内置浏览器P2-20260918 执行笔 A 单元；执行
  // 器在 ToolBrowse.ets——本文件只注册）：browse_act 对当前页执行 scroll/click/type/
  // select/press_key（官方 AIPageInteraction 协议）；联网搜索卡、默认开（拍板「不区分
  // 助手」——随联网域三级闸门同进同出，与 P1 两件同口径）；高危动作静态拦截（词表 +
  // password/submit 属性，A 笔形态恒拒）；settle 有界采样后重拍覆写页态
  toolRegistry.register({
    name: TOOL_BROWSE_ACT,
    group: TOOL_GROUP_WEB,
    title: '操作网页',
    desc: BROWSE_ACT_DESC,
    parametersJson: BROWSE_ACT_SCHEMA,
    defaultEnabled: true,
    executor: new BrowseActExecutor(),
    // 确认链接线（2026-09-19 HTTP 请求工具笔注册表化）：browseActNeedsConfirm 与
    // grantBrowseApproval 两函数体零改动，仅接线方式自 ChatToolRoundCtrl 编排层硬编码改
    // 注册表分发（preflight 预检收集 + onApproved 允许后授予）
    preflight: browseActNeedsConfirm,
    onApproved: (convId: string): void => { grantBrowseApproval(convId); }
  });
  // HTTP 请求（2026-09-19 任务书-HTTP请求工具-20260919 执行笔；执行器与预检在
  // ToolHttp.ets——独立工具域先拆，本文件只注册）：★ 2026-09-20 HTTP 请求独立域笔——
  // 自联网搜索卡（TOOL_GROUP_WEB）移出、单列 TOOL_GROUP_HTTP 卡，不再进 WEB_DOMAIN_TOOLS
  //（无联网三级闸门：联网搜索总开关与会话「联网」开关均不影响本件，启用面只由助手工具页
  // 本卡开关决定）；defaultEnabled=false 不进默认集合（true = 静默向存量助手发放写能力，
  // 不可接受，用户须在工具页手动开）。写方法（POST/PUT/DELETE/PATCH）经 preflight 逐次确认
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
  // 帮助中心检索（2026-09-05 控制台助手）：defaultEnabled=false——不进普通助手默认集合，
  // 仅控制台助手 seed 显式启用（普通助手工具页签可手动开，零污染默认态）
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
  // 设置修改（2026-09-05 控制台助手设置写工具，决明拍板白名单六键 + 方案 A 直改 + 回执）：
  // defaultEnabled=false——true 会进「未配置列」普通助手的默认集合，违背「仅控制台助手
  // 可用」拍板；开关控制两层 = 控制台 seed 显式列 + 工具页签反向拦截（其他助手开 = 回弹
  // + toast）；desc 与 schema 均自 SET_PREF_WHITELIST 动态生成（零双源，白名单演进只动 map）
  toolRegistry.register({
    name: TOOL_SET_APP_PREFERENCE,
    group: TOOL_GROUP_APP,
    title: '修改应用设置',
    desc: buildSetPrefDesc(),
    parametersJson: buildSetPrefSchema(),
    defaultEnabled: false,
    executor: new SetAppPreferenceExecutor()
  });
  // 设置查询（2026-09-06 设置读工具，CherryStudio diagnose.config 读取面同思路——读写
  // 分离两工具，调研档 docs/调研-设置状态读取工具-20260906.md；决明拍板只对控制台助手
  // 开放且可关闭）：defaultEnabled=false + console-exclusive 反向拦截同 set_app_preference；
  // 白名单复用 SET_PREF_WHITELIST 读写同源（能改的就能查，演进零双源）；desc 教「问状态
  // 先查实不猜测」，与写工具「明确要求才改」调用纪律互补互不污染
  toolRegistry.register({
    name: TOOL_GET_APP_PREFERENCE,
    group: TOOL_GROUP_APP, // 独占件全收应用管理卡（2026-09-18 分类卡轴——只读查询也归此卡，普通助手整卡受限不混排）
    title: '查询应用设置',
    desc: buildGetPrefDesc(),
    parametersJson: '{"type":"object","properties":{}}',
    defaultEnabled: false,
    executor: new GetAppPreferenceExecutor()
  });
  // 系统提示词编辑（2026-09-06 提示词读写域，域实现在 ToolPrompts.ets）：
  // defaultEnabled=false + console-exclusive 反向拦截同 set_app_preference
  toolRegistry.register({
    name: TOOL_EDIT_SYSTEM_PROMPT,
    group: TOOL_GROUP_APP,
    title: '编辑系统提示词',
    desc: buildEditSystemPromptDesc(),
    parametersJson: EDIT_SYSTEM_PROMPT_SCHEMA,
    defaultEnabled: false,
    executor: new EditSystemPromptExecutor()
  });
  // 会话提示词库管理（同域；删除不开放——跳过 UI 确认链不可逆，desc 指引手动删除）
  toolRegistry.register({
    name: TOOL_MANAGE_PROMPTS,
    group: TOOL_GROUP_APP,
    title: '管理会话提示词',
    desc: buildManagePromptsDesc(),
    parametersJson: MANAGE_PROMPTS_SCHEMA,
    defaultEnabled: false,
    executor: new ManagePromptsExecutor()
  });
  // 功能模型三槽设置（2026-09-08 功能模型域，2026-09-10 加记忆提取模型槽；域实现在
  // ToolFunctional.ets）：defaultEnabled=false + console-exclusive 反向拦截同 set_app_preference
  toolRegistry.register({
    name: TOOL_SET_FUNCTIONAL_MODEL,
    group: TOOL_GROUP_APP,
    title: '设置功能模型',
    desc: buildSetFunctionalModelDesc(),
    parametersJson: SET_FUNCTIONAL_MODEL_SCHEMA,
    defaultEnabled: false,
    executor: new SetFunctionalModelExecutor()
  });
  // 生成提示词编辑（同域，标题生成 / 记忆整理 / 记忆优化 / 文字识别四槽，★ 2026-09-11 加
  // 第三槽、★ 2026-09-17 加第四槽，与 FunctionalModelPage 各卡「提示词」键同步开放）：
  // get/set/reset 三 action 对齐 edit_system_prompt 形制；★ 2026-09-17 识别槽加入后 title
  // 去旧名——原「编辑标题与记忆提示词」的涵盖论证（「记忆提示词」涵盖整理与优化两类）在
  // 识别槽上不再成立，行名对用户失实，改为域级「编辑提示词」（未来加槽不再过时）
  toolRegistry.register({
    name: TOOL_EDIT_TITLE_PROMPT,
    group: TOOL_GROUP_APP,
    title: '编辑提示词',
    desc: buildEditTitlePromptDesc(),
    parametersJson: EDIT_TITLE_PROMPT_SCHEMA,
    defaultEnabled: false,
    executor: new EditTitlePromptExecutor()
  });
  // 用量统计查询（2026-09-08 用量统计工具域，域实现在 ToolUsageStats.ets）：只读工具——
  // 读用量统计页三档的总览六格 + Token 四格 + 模型排行 Top10，零写零广播；
  // defaultEnabled=false + console-exclusive 反向拦截同 set_app_preference
  toolRegistry.register({
    name: TOOL_GET_USAGE_STATS,
    group: TOOL_GROUP_APP, // 独占件全收应用管理卡（2026-09-18 分类卡轴——只读查询也归此卡，普通助手整卡受限不混排）
    title: '读取用量统计',
    desc: buildGetUsageStatsDesc(),
    parametersJson: GET_USAGE_STATS_SCHEMA,
    defaultEnabled: false,
    executor: new GetUsageStatsExecutor()
  });
  // 记忆检索（2026-09-13 记忆按需读取，方案 §2.3；执行器在 MemoryGen.ets——记忆域 IO
  // 归口，本文件只注册）：defaultEnabled=false 不进任何助手默认集合；★ 声明不走
  // assistants.tools——模式驱动（读取方式 = 按需读取且四闸放行时由 ChatSendCtrl 追加，
  // 本注册仅供注册表按名取定义与执行器）；工具页按 MODE_DRIVEN_TOOLS 过滤不出页。
  // desc = 何时查记忆的唯一引导（能力单源红线——零 system prompt 改动）
  toolRegistry.register({
    name: TOOL_SEARCH_MEMORY,
    group: TOOL_GROUP_MEMORY,
    title: '检索记忆',
    // ★ 2026-09-21 剥离笔（决策 10）：末句补指向知识库的反向排除——只点**域名**不点工具名
    //（inject 模式下知识库工具可能未声明，点名会诱导模型调用未声明工具白耗一轮——既有红线，
    // 见下方 search_chats 注册块注释）
    desc: '检索用户的长期记忆库。需要了解用户的偏好、背景、身份信息或用户以前交代过的事实时调用。返回按相关度排序的记忆条目。本工具只管关于用户本人的信息。与用户无关的领域知识，例如术语、设定、规范或事物背景，应查知识库。',
    parametersJson: '{"type":"object","properties":{"query":{"type":"string",' +
      '"description":"检索关键词，多个用空格分隔。"}}, "required":["query"]}',
    defaultEnabled: false,
    executor: new SearchMemoryExecutor()
  });
  // 跨会话检索（2026-09-13 跨会话检索，方案-跨会话检索-20260913；执行器在
  // ToolChatSearch.ets——独立工具域先拆，本文件只注册）：defaultEnabled=false 不进默认
  // 集合，助手工具页常规开关（用户显式开启才参与）；desc = 何时检索历史会话的唯一引导
  //（能力单源红线——零 system prompt 改动；与记忆划界但不点 search_memory 工具名——
  // inject 模式下该工具未声明，点名会诱导模型调用未声明工具白耗一轮）；隐私四闸见
  // ToolChatSearch 头注释（locked 排除 / 敏感跳过 / 隐私会话不声明 / 当前会话中转键排除）
  toolRegistry.register({
    name: TOOL_SEARCH_CHATS,
    group: TOOL_GROUP_LOCAL,
    title: '检索历史会话',
    desc: '跨会话检索用户的历史聊天记录。用户提到之前聊过、上次讨论过的话题，或需要找回某次对话的具体内容时调用。返回按相关度排序的消息片段，附会话标题与日期。长期稳定的用户信息（偏好、背景、身份）应检索记忆库而非本工具。',
    parametersJson: '{"type":"object","properties":{"query":{"type":"string",' +
      '"description":"检索关键词，多个用空格分隔。"}}, "required":["query"]}',
    defaultEnabled: false,
    executor: new SearchChatsExecutor()
  });
  // 读取历史会话（2026-09-19 跨会话记忆深化笔，任务书-跨会话记忆深化-20260919；执行器在
  // ToolChatSearch.ets——同域两工具，本文件只注册）：内置第 23 件，get_chats 两动作
  //（list 最近会话清单 / read 按标题定位读消息原文），defaultEnabled=false 不进默认集合
  // 不入 seed（与 search_chats 同款——非立身能力，用户显式开）。desc 数字自域常量动态拼
  //（禁嵌时变值，RikkaHub #1356 缓存教训）；外泄防线 = desc 约束句 + 工具卡审计（拍板 4，
  // 不加硬守卫）；隐私闸 = isCrossSessionTool 双件同闸（隐私会话两件均不声明）
  toolRegistry.register({
    name: TOOL_GET_CHATS,
    group: TOOL_GROUP_LOCAL,
    title: '读取历史会话',
    desc: buildGetChatsDesc(),
    parametersJson: GET_CHATS_SCHEMA,
    defaultEnabled: false,
    executor: new GetChatsExecutor()
  });
  // 知识库检索（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921；执行器在
  // ToolKnowledge.ets——独立工具域先拆，本文件只注册）：内置第 25 件，search_knowledge
  // 两动作（search 按关键词检索条目 / list 看条目清单），defaultEnabled=false 不进默认集合
  // 不入 seed（与 search_chats / get_chats 同款——非立身能力，用户显式开）；desc 三段式
  //（调用时机 / 返回形态 / 划界）在域件、**不点未声明工具的具名**（inject 模式下
  // search_memory 可能未声明，点名会诱导模型白耗一轮——同上条 get_chats 红线）。
  // 隐私闸 = 无（知识库非会话内容，不属 isCrossSessionTool 双件——见域件头注释）
  toolRegistry.register({
    name: TOOL_SEARCH_KNOWLEDGE,
    group: TOOL_GROUP_KNOWLEDGE,
    title: '检索知识库',
    desc: buildSearchKnowledgeDesc(),
    parametersJson: SEARCH_KNOWLEDGE_SCHEMA,
    defaultEnabled: false,
    executor: new SearchKnowledgeExecutor()
  });
  // 知识库管理（2026-09-21 知识库第二笔下本，任务书-知识库写入口与上限放宽-20260921；执行器
  // 在 ToolKnowledge.ets 同文件）：内置第 26 件，manage_knowledge 七动作（list 两形态 /
  // get 与 read_file 读回 / create_book 建库 / create / update / delete 条目三写），
  // defaultEnabled=false 不进默认集合
  // 不入 seed（非立身能力，用户显式开）；desc 三段式（调用时机 / 逐动作用法 / 划界与限额）在
  // 域件，**划界句只点域名不点工具名**（inject 模式或助手未启用知识库时 search_memory 可能未
  // 声明，点名会诱导模型白耗一轮——同 search_chats 红线）。与上件的分工 = 读写分界：检索件
  // 只读、本件是唯一写口；两件同归「知识库」卡（2026-09-21 剥离笔建的卡，本笔只加成员——
  // **不动卡片轴 / 组序 / 独占名单**）；隐私闸 = 无（知识库非会话内容，不属 isCrossSessionTool
  // 双件——见域件头注释）
  toolRegistry.register({
    name: TOOL_MANAGE_KNOWLEDGE,
    group: TOOL_GROUP_KNOWLEDGE,
    title: '管理知识库',
    desc: buildManageKnowledgeDesc(),
    parametersJson: MANAGE_KNOWLEDGE_SCHEMA,
    defaultEnabled: false,
    executor: new ManageKnowledgeExecutor()
  });
  // 记忆管理（2026-09-13 记忆管理工具，任务书-记忆管理工具-20260913；执行器在
  // ToolMemoryManage.ets——独立工具域先拆，本文件只注册）：list/create/update/delete 四
  // action，update/delete 按记忆原文精确匹配定位（纯逻辑在 MemoryText 记忆管理节）；
  // defaultEnabled=false，delete 开放（记忆删除无级联确认链，UI 记忆页有完整管理兜底）；
  // 管理面独立——记忆总开关/读取方式/memoryInject 均不挂闸（与 UI「停用后仍可查看、编辑和
  // 删除」同口径，声明零特判）。★ 2026-09-21 剥离笔：非独占件（原 console-exclusive——见上方
  // 常量注释的决策 13 依据），归「记忆」卡；作用域由 MEMORY_EXEC_ASSISTANT_KEY 决定
  toolRegistry.register({
    name: TOOL_MANAGE_MEMORY,
    group: TOOL_GROUP_MEMORY,
    title: '管理长期记忆',
    desc: buildManageMemoryDesc(),
    parametersJson: MANAGE_MEMORY_SCHEMA,
    defaultEnabled: false,
    executor: new ManageMemoryExecutor()
  });
  // 技能加载（2026-09-13 技能层，方案 §2.3；执行器在 ToolSkill.ets——独立工具域先拆，本
  // 文件只注册）：★ 模式驱动第二件，defaultEnabled=false 不进任何助手默认集合；声明不走
  // assistants.tools——该助手启用了至少一件现存技能时由 ChatSendCtrl 追加（清单与声明同闸：
  // 零启用 = 零注入零声明）；工具页按 MODE_DRIVEN_TOOLS 过滤不出页。
  // desc = 何时加载技能的唯一引导（能力单源红线——零 system prompt 改动；与清单头行
  // 「先调用 use_skill 加载对应技能正文再作答」互证互补）
  toolRegistry.register({
    name: TOOL_USE_SKILL,
    group: TOOL_GROUP_SKILL,
    title: '加载技能',
    desc: '加载技能的完整说明书。系统提示词可用技能清单列出每个技能的名称与触发描述，当用户任务与某技能的触发描述匹配时调用本工具，name 逐字取自清单，每次只加载一件。清单为空或无匹配时不得调用。加载后按技能正文执行任务。技能若附带文件，返回内容末尾的 skill_resources 会列出文件名，需要某个文件时再次调用本工具并填 file 参数取用。',
    parametersJson: USE_SKILL_SCHEMA,
    defaultEnabled: false,
    executor: new UseSkillExecutor()
  });
  // 管理技能（2026-09-16 技能管理工具笔，任务书 §3.1；执行器与 use_skill 同居
  // ToolSkill.ets——两工具同文件先例 = ToolPrompts，本文件只注册）：create_skill 整体
  // 退役并入（对标 manage_memory / manage_prompts 同一形制）。★ 技能管理卡非独占件
  //（不进 CONSOLE_EXCLUSIVE_TOOLS——普通助手技能管理卡开关可开，现状零收窄）；也非模式驱动
  //（声明由工具页技能管理卡开关决定，不走 assistants.skills 通道）。schema/desc 的上限数字
  // 随 SkillText 常量单源动态拼（禁字面量双源，RikkaHub #1356 缓存教训）；desc 末句
  // 「创建成功后告知未启用」= 落库惰性口径（启用仍须用户逐助手手动开）；无 delete——
  // desc 与错误路径指引 设置 → 技能库 手动删
  toolRegistry.register({
    name: TOOL_MANAGE_SKILLS,
    group: TOOL_GROUP_SKILL,
    title: '管理技能',
    desc: buildManageSkillsDesc(),
    parametersJson: MANAGE_SKILLS_SCHEMA,
    defaultEnabled: false,
    executor: new ManageSkillsExecutor()
  });
  // 服务商与模型读取（2026-09-13 工具补齐三件，任务书 §2.1；执行器在 ToolProvider.ets——
  // 独立工具域先拆，本文件只注册）：只读查询服务商清单/模型清单/当前会话生效连接；
  // defaultEnabled=false + console-exclusive 反向拦截同 get_usage_stats；★ 不读密钥与
  // 自定义头明文——只回条目计数与布尔（三敏感列零出现，断言负向钉）
  toolRegistry.register({
    name: TOOL_GET_PROVIDER_CONFIG,
    group: TOOL_GROUP_APP,
    title: '查询服务商与模型',
    desc: buildGetProviderConfigDesc(),
    parametersJson: GET_PROVIDER_CONFIG_SCHEMA,
    defaultEnabled: false,
    executor: new GetProviderConfigExecutor()
  });
  // 费用估计读取（2026-09-13 工具补齐三件，任务书 §2.2；执行器在 ToolCostStats.ets——
  // 独立工具域先拆，本文件只注册）：只读查询费用估计页三档的四格/排行/用途分布；
  // defaultEnabled=false + console-exclusive 反向拦截同 get_usage_stats；四格构造与费用页
  // 同源（UsageStatsCalc.buildCostCells 单源，页面私有方法已外迁）
  toolRegistry.register({
    name: TOOL_GET_COST_STATS,
    group: TOOL_GROUP_APP,
    title: '读取费用估计',
    desc: buildGetCostStatsDesc(),
    parametersJson: GET_COST_STATS_SCHEMA,
    defaultEnabled: false,
    executor: new GetCostStatsExecutor()
  });
  hilog.info(DOMAIN, TAG, '内置工具已注册：%{public}d 项', toolRegistry.all().length);
}

// 联网搜索执行器（2026-09-03 第三批①，Cube BuiltinTools SearchWebExecutor 同构；
// ★ 2026-09-10 多引擎一期改分发）：query 空守卫 → query 加工（cleanSearchQuery 口语前缀
// 清洗 + normalizeRelativeTime 新闻意图相对时间归一，SearchQueryClean.ets 纯函数）→
// dispatchSearch 注册表编排（读偏好 → fallback 解析 → Asset 取钥 → 引擎 handler 分发，
// common/search/SearchEngineRegistry.ets）——执行器壳只管载荷组装与终态语义：
// · 缺 key / 配额错 → error 文案带配置路径（注册表编排层产）+ description 已声明勿重试；
// · 零结果 → results:[] + summary 明确「未返回结果」语义（优化候选 A3 销账，变更记录
//   1304 行在案）——不再静默空载荷让模型猜。
// 引擎与 key 配置 = 设置 → 联网搜索（SearchEnginePage）；description 引用规范原文不动
class SearchWebExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    let query: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const raw = parsed['query'];
      if (typeof raw === 'string') {
        query = raw.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    if (query === '') {
      return Promise.resolve(JSON.stringify({ error: '搜索关键词不能为空' }));
    }
    const normalized: string = normalizeRelativeTime(cleanSearchQuery(query), new Date());
    return dispatchSearch(normalized).then((out: WebSearchOutcome): string => {
      if (!out.success) {
        return JSON.stringify({ error: out.errorMessage });
      }
      const payload: SearchResultOutputPayload = {
        query: out.query, searchEngine: out.searchEngine,
        results: out.references,
        summary: out.references.length === 0 ?
          '本次搜索未返回任何结果。请更换更具体的关键词或改用自己的知识回答，不要用同一关键词重复搜索。' :
          out.contentForAI
      };
      return JSON.stringify(payload);
    });
  }
}

// 网页读取执行器（Cube ScrapeWebExecutor 同构；query 兼容键 = 模型传参脏的防御，
// Cube :160 同款）。★ 2026-09-11 单向绑定兜底守卫（B 案）：声明过滤已把联网域两件一并
// 剔除（ChatSendCtrl.webDomainAllowed），此处兜住「轮内切开关」与绕过声明过滤的路径；
// 谓词与文案家族同 SearchEngineRegistry.dispatchSearch 的总开关守卫——只补全局这一维
//（execute(argsJson) 无上下文，会话级/助手级两维由声明层负责，范围克制）
class ScrapeWebExecutor implements ToolExecutor {
  execute(argsJson: string): Promise<string> {
    if (!isSearchServiceEnabled()) {
      return Promise.resolve(JSON.stringify({
        error: '联网搜索已关闭。请让用户在 设置 → 联网搜索 打开总开关后重试，本次不要重复读取。' }));
    }
    let rawUrl: string = '';
    try {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const url = parsed['url'];
      const query = parsed['query'];
      if (typeof url === 'string' && url.trim() !== '') {
        rawUrl = url.trim();
      } else if (typeof query === 'string') {
        rawUrl = query.trim();
      }
    } catch (e) {
      return Promise.resolve(JSON.stringify({ error: '参数解析失败' }));
    }
    if (rawUrl === '') {
      return Promise.resolve(JSON.stringify({ error: '网页 URL 不能为空' }));
    }
    return fetchUrlContent(rawUrl).then((out: WebFetchOutcome): string => {
      if (!out.success) {
        return JSON.stringify({ error: out.errorMessage });
      }
      const item: SearchResultItemPayload = {
        index: 1, id: `ref_${Date.now()}`, title: out.title, url: out.url,
        snippet: out.content.replace(/\s+/g, ' ').trim().substring(0, 200)
      };
      const payload: SearchResultOutputPayload = {
        query: out.url, searchEngine: 'url_fetch',
        results: [item], summary: `标题: ${out.title}\n来源: ${out.url}\n\n${out.content}`
      };
      return JSON.stringify(payload);
    });
  }
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

// ── 流式工具调用聚合器（四协议 SseToolDelta → 完整 AiToolCall；每发送轮一实例，
//   ChatSendCtrl.reset 时重建）──
interface AccEntry {
  id: string;
  name: string;
  args: string;
}

export class ToolCallAccumulator {
  private byIndex: Map<number, AccEntry> = new Map<number, AccEntry>();
  private completes: AccEntry[] = []; // index<0（gemini）整调用直落此
  private seq: number = 0; // 无 id 调用的兜底序号

  feed(deltas: SseToolDelta[]): void {
    for (const d of deltas) {
      if (d.index < 0) {
        // 整调用（gemini functionCall / 无序位方言）：name + argsFull 全量直收
        this.completes.push({ id: this.genId(), name: d.name ?? '', args: d.argsFull ?? '{}' });
        continue;
      }
      let entry: AccEntry | undefined = this.byIndex.get(d.index);
      if (entry === undefined) {
        entry = { id: '', name: '', args: '' };
        this.byIndex.set(d.index, entry);
      }
      if (d.id !== undefined) {
        entry.id = d.id;
      }
      // name 双语义（2026-09-06 修复「search_helpsearch_help」重名循环）：nameFull 全量
      // 替换（responses added/done 各带完整名，+= 会拼重名——真机 bugtest 转录实锤，
      // 重名命不中声明集 →「未在本轮启用」→ 模型重试 → 循环至轮上限）；name 分片拼接
      //（openai chat 事实形态——首帧片段续片累拼）
      if (d.nameFull !== undefined) {
        entry.name = d.nameFull;
      } else if (d.name !== undefined) {
        entry.name += d.name;
      }
      if (d.argsFull !== undefined) {
        entry.args = d.argsFull; // 全量替换式（responses done）
      } else if (d.argsDelta !== undefined) {
        entry.args += d.argsDelta; // 增量拼接式
      }
    }
  }

  // 快照（流结束取全量）：id 空 → 生成兜底 id（CubeAgent 同款）；args 空 → '{}' 归一
  snapshot(): AiToolCall[] {
    const calls: AiToolCall[] = [];
    const indices: number[] = [];
    this.byIndex.forEach((_entry: AccEntry, index: number): void => {
      indices.push(index);
    });
    indices.sort((a: number, b: number): number => a - b);
    for (const index of indices) {
      const entry: AccEntry | undefined = this.byIndex.get(index);
      if (entry === undefined) {
        continue;
      }
      calls.push({
        id: entry.id !== '' ? entry.id : this.genId(),
        name: entry.name,
        argsJson: entry.args !== '' ? entry.args : '{}'
      });
    }
    for (const entry of this.completes) {
      calls.push({ id: entry.id, name: entry.name, argsJson: entry.args });
    }
    return calls;
  }

  private genId(): string {
    this.seq++;
    return 'tool_call_' + Date.now() + '_' + this.seq;
  }
}

// ── 工具执行域单例 ──

// ask_user 交互桥：执行轮挂起等用户作答（pendingAnswers 只存内存——进程死亡即丢，
// CubeAgent 同语义；页面销毁走 cancelAllPending 防悬挂）
export class ToolRuntime {
  private pendingAsks: Map<string, (answer: string) => void> = new Map();
  // browse_act 确认桥（2026-09-18 P2 B 单元，照 pendingAsks 形制）：高危动作挂起等用户在
  // 确认卡上点「允许一次 / 拒绝」（pendingConfirms 同样只存内存；resolve false = 拒绝）
  private pendingConfirms: Map<string, (approved: boolean) => void> = new Map();
  // 会话级「始终允许」白名单（2026-09-20 笔 C；方案 §2.6）——用户在确认卡点「本会话内允许」
  // 后，本会话内该工具不再弹确认卡。key = conversationId + '|' + toolName；**只存内存**：
  // 不落库、不进 AppStorage（convId 由调用方经宿主 conversationId() 快照传入，与确认链
  // 「桥内不自读中转键」同纪律——assert-app-domain 125 组负向钉守此线），进程死亡即失效。
  // ★ 结构取 Set 而非方案原文的 Map<string, boolean>：键即全部信息、值恒真，语义等价（申报）。
  // 有界性：条目数受「会话数 × 工具数」天然约束，量级 KB，不设显式上限（只进不出的是键集合，
  // 不是数据；用户切会话只增不删，故此处写明口径）
  private sessionAllows: Set<string> = new Set<string>();

  // 挂起等用户作答（ChatSendCtrl 工具轮消费；resolve 时以答案 JSON 串续跑）
  waitAsk(callId: string): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void) => {
      this.pendingAsks.set(callId, resolve);
    });
  }

  // 用户提交答案（ChatPage ask 卡上行；callId 不在挂起集 = 已取消/已答——静默吞防误触）
  resolveAsk(callId: string, answerJson: string): void {
    const resolve: ((value: string) => void) | undefined = this.pendingAsks.get(callId);
    if (resolve !== undefined) {
      this.pendingAsks.delete(callId);
      resolve(answerJson);
    }
  }

  // 挂起等用户确认高危浏览动作（工具轮域消费；resolve 值 = 是否允许本次执行）
  waitBrowseConfirm(callId: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      this.pendingConfirms.set(callId, resolve);
    });
  }

  // 用户在确认卡上作答（ChatPage 确认卡上行；callId 不在挂起集 = 已取消/已答——静默吞）
  resolveBrowseConfirm(callId: string, approved: boolean): void {
    const resolve: ((value: boolean) => void) | undefined = this.pendingConfirms.get(callId);
    if (resolve !== undefined) {
      this.pendingConfirms.delete(callId);
      resolve(approved);
    }
  }

  // 会话级免询问授予（唯一写点 = 用户按确认卡第三键那一刻，见 ChatToolRoundCtrl.awaitBrowseConfirm）
  grantSessionAllow(conversationId: string, toolName: string): void {
    if (conversationId === '' || toolName === '') {
      return; // 空键不落（防全空串键命中一切）
    }
    this.sessionAllows.add(conversationId + '|' + toolName);
  }

  // 会话级免询问查询（唯一读点 = 门闸，见 ChatToolRoundCtrl.sessionAllowHit）
  isSessionAllowed(conversationId: string, toolName: string): boolean {
    if (conversationId === '' || toolName === '') {
      return false; // 空键恒不命中（与授予侧守卫成对；fail-safe 方向）
    }
    return this.sessionAllows.has(conversationId + '|' + toolName);
  }

  // 兜底取消（停止/销毁/轮次收尾）：未答的挂起全部以取消 JSON 续跑（模型可感知用户中止）；
  // ★ 确认挂起同轮连带清（resolve false = 视为拒绝，不留悬挂 Promise——内存防线成对）
  cancelAllPending(): void {
    this.pendingAsks.forEach((resolve: (value: string) => void): void => {
      resolve(JSON.stringify({ cancelled: true, error: '用户中止了本次提问' }));
    });
    this.pendingAsks.clear();
    this.pendingConfirms.forEach((resolve: (value: boolean) => void): void => {
      resolve(false);
    });
    this.pendingConfirms.clear();
  }
}

export const toolRuntime: ToolRuntime = new ToolRuntime();

// 工具执行（单调用包装；失败转 error JSON 不炸轮次——RikkaHub execute 同语义）：
// args 解析失败原样透传（模型自纠）；executor 抛错包装 {"error": ...}。
// ★ 本函数自身无并发防护义务——同一轮多调用在 ChatToolRoundCtrl 经 lanes（Promise.all）
// 并发执行（日志「工具并行」打点），executor 内涉及计数/快照回执的（如 manage_memory 的
// count+1）只承诺文案级一致，写冲突由 DB 行级操作与 affected-0 抛错防御兜底
export async function executeToolCall(entry: ToolEntry, argsJson: string): Promise<string> {
  try {
    return await entry.executor.execute(argsJson);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '工具 %{public}s 执行失败：%{public}s', entry.name, (e as Error).message);
    return JSON.stringify({ error: (e as Error).message });
  }
}

// 工具结果文本截断（数据有界红线——超长结果只留头部；RikkaHub 32K 同思路，aicontrol 取 8K
// 手机端保守值）。截断尾标提示模型结果被裁。
// ★ 2026-09-03 自检 P1-3 修复：搜索类结果 JSON（scrape_web summary 复述全文，转义后常超
// 8192）超限时不再硬截 JSON 中间——先结构化只裁 summary 键再序列化（results 保整 =
// 引文卡回放数据源不丢），模型恒收合法 JSON；非搜索载荷形态仍走旧硬截兜底
export function clipToolResult(result: string, maxChars: number = 8192): string {
  if (result.length <= maxChars) {
    return result;
  }
  const structured: string = clipSearchPayload(result, maxChars);
  if (structured !== '') {
    return structured;
  }
  return result.substring(0, maxChars) + '…[结果过长已截断]';
}

// 搜索类载荷结构化截断（P1-3）：只裁 summary（模型阅读面）保 results 整串——引文卡唯一
// 数据源（ChatMessageItem.toolSearchRefs 解析 results 数组，坏 JSON 回空 = 引文卡静默消失）。
// 非搜索形态（无 summary/results 键）或 results 单串即超限 → '' 由调用方走旧硬截兜底。
// 预算算法：summary 按溢出量递减裁剪 + 尾标重试序列化（JSON 转义膨胀——\n→\\n 等使预算
// 失真，每轮按 5% 回退收敛；至多十余轮 stringify，单次执行路径开销可忽略）
const CLIP_TAIL: string = '…[内容过长已截断]';

function clipSearchPayload(result: string, maxChars: number): string {
  try {
    const rec = JSON.parse(result) as Record<string, Object>;
    const summaryRaw: Object = rec['summary'];
    const resultsRaw: Object = rec['results'];
    if (typeof summaryRaw !== 'string' || !Array.isArray(resultsRaw)) {
      return '';
    }
    const summary: string = summaryRaw as string;
    let json: string = JSON.stringify(rec);
    if (json.length <= maxChars) {
      return json;
    }
    const overflow: number = json.length - maxChars;
    let cut: number = summary.length - overflow - CLIP_TAIL.length;
    while (cut > 0) {
      rec['summary'] = summary.substring(0, cut) + CLIP_TAIL;
      json = JSON.stringify(rec);
      if (json.length <= maxChars) {
        return json;
      }
      cut = Math.floor(cut * 0.95);
    }
    return '';
  } catch (e) {
    return '';
  }
}
