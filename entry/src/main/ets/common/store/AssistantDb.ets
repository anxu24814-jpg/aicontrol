// 助手存储域（2026-09-01 助手域新建，照 PromptTemplateDb 域拆先例——ChatDb 加助手 CRUD
// 必超 400 红线）：assistants 表 CRUD + conversations.assistantId 会话引用读写。
// 语义（参照 RikkaHub 助手、裁剪至 aicontrol 已支持能力——裁剪清单与理由见
// docs/调研与待办-助手与提示词变量.md）：
// ①助手 = 名称 + 提示词两字段（v1 极简）——提示词支持 {{date}}/{{time}} 等变量（发送前
//   应用层替换，PromptVariables.ets；替换对任意注入源统一生效，非助手独占）；
// ②引用跟随——会话存助手 id 引用，助手修改后引用会话下次发送自动用新版；
// ③注入优先级（ChatPromptState 解析，★2026-09-04 归属与注入解耦——决明拍板：会话恒归属
//   一个助手，提示词注入 = 独立开关：开 = 模板覆盖〔不注入助手提示词〕、关 = 注入归属
//   助手提示词）：会话提示词 > 助手提示词 > 系统提示词；归属助手的高级参数/工具恒生效
//   （不随注入开关清空）；助手与会话提示词选择面不再互斥（旧单注入语义撤销）；
//   ★2026-09-04 晚归属定稿（「跟随当前」语义撤销）：行 ''（存量未绑定）= 内置默认助手兜底
//   显式归属，无行新会话 = 面板覆盖 ?? 当前助手 ?? 默认助手（发送落行实体值同源）；
// ④删助手 = 级联删除（2026-09-01 会话历史绑定助手改造，拍板 = RikkaHub 删助手同款硬
//   级联无软删除）：deleteAssistantCascade 同事务多删（messages → conversations →
//   assistants 行，防孤儿消息/会话；v35 起加删 assistant_memories 该助手记忆库行——
//   库跟着人走，与全局 memories 置空保留的跨会话资产口径刻意不同；v41 起加删
//   memory_snapshots 该助手库的记忆优化历史快照——同「库跟着人走」口径，防孤儿行堆积）；
//   确认文案写明「名下 N 个会话一并删除不可恢复」；
//   删除当前助手由调用方（AssistantPage）把 active 键重置默认 + 列表重拉广播；
// ⑤内置默认助手（2026-09-01 反馈轮 2：助手页保留一张内置卡禁删；反馈轮 3 收紧：禁改
//   ——提示词恒与系统提示词同步）= 固定 id ASSISTANT_DEFAULT_ID 行（名「默认助手」恒定）；
// ⑥内置控制台助手（2026-09-05 控制台助手：帮助问答内置助手）= 固定 id ASSISTANT_CONSOLE_ID
//   行——禁删；名称与提示词禁改（提示词 = CONSOLE_ASSISTANT_PROMPT 常量读时联结，模型
//   绑定/工具/高级设定照常可改）；tools seed 显式列（search_help 核心 + 2026-09-05 第二笔
//   set_app_preference + 2026-09-06 扩面 edit_system_prompt/manage_prompts + 同日设置读
//   工具 get_app_preference + 2026-09-08 功能模型域两件与 get_usage_stats + 2026-09-13
//   manage_memory 记忆管理 + 同日 create_skill 创建技能（2026-09-16 并入 manage_skills
//   管理技能），存量迁移判据与不复活语义见
//   ensureConsoleAssistant 注释）；
//   助手页恒列第 2 位——★2026-09-22 撤除（助手自定义列表序笔）：位置不再由 id 决定，
//   两张内置卡的序与其他助手同源（assistants.sortOrder），用户可拖到任意位置。
//   ensureDefaultAssistant 启动幂等兜底（无行才插）；deleteAssistantCascade 守卫禁删（-1）；
//   ★提示词同步机制 = **读时联结**（syncDefaultPrompt）：行
//   prompt 列恒 '' 不落盘不双写——展示/注入读取时以 queryGlobalTemplate 内容替换，单一
//   真源 = prompt-global 行（系统提示词页保存/恢复即时反映，无缓存无同步窗口无清删面）；
//   助手提示词页对默认卡只读（无输入/无变量卡/无保存键，仅内容展示框）。
// ⑥分区化（2026-09-01 编辑页改枢纽页，同日按钮区退役）：名称与提示词分页编辑（编辑页
//   名称行卡弹重命名对话框 → updateAssistantName 即时落库〔Key 池/会话重命名同口径〕；
//   提示词二级页「保存」键 → updateAssistantPrompt），各单列 UPDATE；新建 = 列表页「＋」
//   对话框 insert（空提示词）——取消不落行；删除唯一入口 = 列表卡删除键。
// ⑦模型绑定（2026-09-01 模型设置卡，DB v10 三列）：providerId/modelId = 助手级模型绑定
//  （'' = 未绑定；RikkaHub chatModelId 同语义，UI = 编辑页「模型设置」卡，选择即落库不经
//   保存键）+ thinkLevel（思考档位，枚举同 AiTypes.THINKING_OPTIONS，「关闭」项按绑定服务商
//   baseUrl supportsThinkingOff 显隐 = 菜单随模型改变的映射点，同会话页机制）。清删 =
//   删服务商/删模型时 ProviderDb 删除函数级联清列（clearAssistantBindingByProvider/ByModel，
//   同事务）；★发送链覆盖 2026-09-05 落地（调研待办 2）：resolveActiveConnection 四级兜底链
//   第②级 = 会话页所选 > 本绑定 > 全局默认 > 首个启用模型（中途不停）——绑定生效于发送，
//   消费链见 ProviderDb.resolveActiveConnection 头注释。
// ⑧高级设定（2026-09-01 高级设定卡，DB v11 单列）：advancedParams = 采样与上下文参数
//   JSON 串（'' = 未配置 = 全部不发送，请求体零回归；结构/解析在 AiTypes——采样四键仅
//   开关开启才存，contextCount/maxOutput 进过上下文页保存即存，三态语义 = anthropic
//   max_tokens 未配置 8192 现状 / 显式 0 兜底 131072 / 正数用值）。UI = 编辑页「高级设定」
//   卡 → 二级页两行卡 → 采样/上下文两三级页（返回时统一落库，onBackPressed 拦截姿势）。
//   清删 = 删助手整行级联（既有）；删服务商/删模型**不清本列**（采样参数跨模型通用，
//   与 thinkLevel「离开原服务商无意义」语义不同）。发送链 = ChatPromptState.load 解析缓存
//   → ChatSendCtrl 截取+透传 → RequestCompose 四协议方言落点（⑦的模型绑定仍后置）。
// ⑨知识库启用清单（2026-09-21 世界书知识库，DB v38 单列）：knowledge = 助手启用的知识库 id
//   清单 JSON 串（★ '' = 空集合 = 不启用任何知识库，与 skills 列同义、与 tools 列**相反**；
//   解析/序列化单一落点 = KnowledgeText.parse/serializeEnabledKnowledgeIds，本域只存取原串）。
//   UI = 编辑页「知识库」卡 → 助手知识库页（开关组卡逐本一开关，第 11 个被
//   KNOWLEDGE_ENABLED_MAX 拦截）；清删 = 删知识库时 KnowledgeDb.deleteBookCascade 事务内
//   clearKnowledgeRefInAssistants 联动清列（读取侧「启用 ∩ 现存」过滤是第二道保险）；
//   声明链 = 该助手启用集非空时 search_knowledge 进声明（默认助手/普通助手均可开）。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import { nextMessageId, sharedRdbStore } from './ChatDb';
import { deleteAttachmentsForConversations, removeAttachmentFiles } from './AttachmentDb';
import { TOOL_STEP_LIMIT_DEFAULT } from '../providers/ToolLimits';
import { SEARCH_RESULT_COUNT_DEFAULT } from '../search/SearchLimits';
import { PromptTemplateRow, queryGlobalTemplate } from './PromptTemplateDb';
import { clearMemoryAssistantRef, deleteAssistantMemoriesOfAssistant,
  deleteMemorySnapshotsOfAssistant, MEMORY_SCOPE_GLOBAL } from './MemoryDb';

const DOMAIN: number = 0xD5A4;
const TAG: string = 'AssistantDb';

// 内置默认助手固定 id（seed 兜底与禁删守卫共用；UI 判定「无删除键」同用）
export const ASSISTANT_DEFAULT_ID: string = 'assistant-default';
export const ASSISTANT_DEFAULT_NAME: string = '默认助手';

// 内置控制台助手固定 id（2026-09-05 控制台助手——帮助问答内置助手，照默认助手全套先例：
// seed 兜底与禁删守卫共用，助手页恒列第 2 位）
export const ASSISTANT_CONSOLE_ID: string = 'assistant-console';
export const ASSISTANT_CONSOLE_NAME: string = '控制台助手';

// 控制台助手内置路由提示词（CherryStudio「Cherry 小助手」同款分工——帮助全文不进提示词
// 只留路由规则，内容检索走 search_help 工具直读 HelpContent 单源，帮助条目演进零维护）：
// prompt 列恒 '' 读时联结本常量（syncConsolePrompt——与默认助手 syncDefaultPrompt 同机制
// 但联结源是代码常量非 DB 行，升级改提示词下次读取即生效）。
// ★ 2026-09-06 归位式精简（决明拍板）：能力清单与单工具操作细节从提示词删除——可改设置
// 项名单单源在 set_app_preference 的 desc 与 schema（buildSetPrefDesc 白名单动态生成 +
// 枚举约束，随请求下发模型每请求可见），edit_system_prompt/manage_prompts 的使用细节
// （set 整体替换先 get 原文、删除不开放指引手动）同样单源在各自 desc；提示词只留与能力
// 演进无关的行为核心六句（角色 / search_help 路由 / ask_user 澄清 / 写操作策略 / 离题 /
// 风格——末句来源见下方 2026-09-06 晚补注）——此后
// 白名单加键、新增工具默认零改提示词（工具层 desc 自包含即随注册生效），扩面膨胀路径
// 切断；set-pref-tool-check 钉「能力清单不回填」防回潮。写操作策略（明确要求才执行 /
// 问能不能开≠要我改 / 一次一项 / 执行后回执确认 / 做不到指路手动）保留在提示词 = 跨
// 工具语义约束面（社区实证模型会把「能不能开」当「帮我开」，工具 desc 只有逐工具版本）。
// ★ 2026-09-06 晚补第六句：ask_user 澄清路由（问题不具体且直接回答可能误导 → 先确认
// 一个最关键的问题再继续）——对照吸收 Cube 新版帮助助手提示词（未开源，决明提供）的
// 唯一真实增量（决明拍板「吸收」；ask_user 全助手共用，desc 改动会外溢到所有助手，
// 角色级行为落提示词作用域刚好；「只问一个」防连环追问）。其余五句对照判：角色/路由/
// 反编造已有等价、回答 rubric 住在帮助内容写作规范里、主题触发枚举属能力清单反模式不取。
export const CONSOLE_ASSISTANT_PROMPT: string = [
  '你是「AI 控制台」应用内置的控制台助手，专门解答本应用的用法问题。',
  '用户询问本应用的功能或操作时，先调用 search_help 工具检索帮助中心，再依据返回条目的内容回答。',
  '用户的问题不够具体、直接回答可能误导时，先用 ask_user 工具确认一个最关键的问题再继续。',
  '用户要求修改本应用的设置或提示词时，能代办的直接调用对应工具执行，不要只口头指路。仅在用户明确要求后才执行修改，用户问「能不能开」只是在提问，先如实回答，等用户明确要改再执行。一次只执行用户点名的那一项，执行后用一句话向用户确认改了什么与当前状态。工具做不到的如实说明，并指引用户到设置中手动修改。',
  '用户提出与本应用无关的问题时可以正常回答，同时说明你更擅长解答本应用的用法。',
  '回答保持简洁，操作步骤按帮助条目的写法给出入口路径。'
].join('\n');

// 控制台助手启用工具 seed 值（显式 JSON 串：search_help 核心 + ask_user 澄清 + 时间基础件
// + set_app_preference 设置直改〔2026-09-05 第二笔〕+ get_app_preference 设置状态查询
//〔2026-09-06 设置读工具〕+ edit_system_prompt/manage_prompts 提示词读写〔2026-09-06 扩面〕
// + set_functional_model/edit_title_prompt 功能模型域〔2026-09-08 扩面〕+ get_usage_stats
// 用量统计查询〔2026-09-08 第二笔〕+ manage_memory 记忆管理〔2026-09-13 记忆管理工具笔〕
// + manage_skills 管理技能〔create_skill 2026-09-13 会话中创建技能笔入列，2026-09-16
// 技能管理工具笔整体改名退役并入——控制台可直建可改可读（薄路径）〕
// + get_provider_config/get_cost_stats 服务商与费用两读件〔2026-09-13 工具补齐三件笔〕，
// 仅控制台助手默认开；用户可在工具页签自行关——可关闭
// 非锁定，与 search_help 立身项不同；不带联网双工具——帮助语料全在本地，联网检索无益只增
// 时延）
const CONSOLE_ASSISTANT_TOOLS: string =
  '["search_help","ask_user","get_time_info","set_app_preference","get_app_preference","edit_system_prompt","manage_prompts","set_functional_model","edit_title_prompt","get_usage_stats","manage_memory","manage_skills","get_provider_config","get_cost_stats"]';

// 历史 seed 串（逐级迁移判据，RDB 逐级迁移铁律同哲学——★ 判据按标记代数分流：
// 标记 ''（V2 时代前设备）只认 V1；标记 '1'（V2 时代设备）只认 V2。精确匹配 = 用户从未
// 动过工具列才升；includes 等宽松匹配会把用户已自定义的列也改掉（复活用户关闭态违背
// 拍板），禁用。★ 标记 '1' 且列恰等 V1 = 用户显式关闭 set_app_preference 后剩余三件
// 序列化产物（2026-09-05 真机实锤的复活循环形态）——在 V2 代判据下不匹配任何分支，
// 关闭态保护）
const CONSOLE_ASSISTANT_TOOLS_V1: string = '["search_help","ask_user","get_time_info"]';
const CONSOLE_ASSISTANT_TOOLS_V2: string =
  '["search_help","ask_user","get_time_info","set_app_preference"]';
const CONSOLE_ASSISTANT_TOOLS_V3: string =
  '["search_help","ask_user","get_time_info","set_app_preference","edit_system_prompt","manage_prompts"]';
const CONSOLE_ASSISTANT_TOOLS_V4: string =
  '["search_help","ask_user","get_time_info","set_app_preference","get_app_preference","edit_system_prompt","manage_prompts"]';
const CONSOLE_ASSISTANT_TOOLS_V5: string =
  '["search_help","ask_user","get_time_info","set_app_preference","get_app_preference","edit_system_prompt","manage_prompts","set_functional_model","edit_title_prompt"]';
const CONSOLE_ASSISTANT_TOOLS_V6: string =
  '["search_help","ask_user","get_time_info","set_app_preference","get_app_preference","edit_system_prompt","manage_prompts","set_functional_model","edit_title_prompt","get_usage_stats"]';
// ★ V7 = 十一件旧串快照（2026-09-13 会话中创建技能笔升代）——**存的是旧代串作恰等判据**，
// 不是新值：标记 '6' 且列恰等本串（= 用户从未动过的十一件代）才升当前代；新值在无
// V 后缀的 CONSOLE_ASSISTANT_TOOLS（同历史代常量语义，V{n} 恒指第 n 代检查完成时的串）
const CONSOLE_ASSISTANT_TOOLS_V7: string =
  '["search_help","ask_user","get_time_info","set_app_preference","get_app_preference","edit_system_prompt","manage_prompts","set_functional_model","edit_title_prompt","get_usage_stats","manage_memory"]';
// ★ V8 = 十二件旧串快照（2026-09-13 工具补齐三件笔升代）——判据语义同 V7：标记 '7' 且列恰等
// 本串（= 用户从未动过的十二件代）才升当前十四件
const CONSOLE_ASSISTANT_TOOLS_V8: string =
  '["search_help","ask_user","get_time_info","set_app_preference","get_app_preference","edit_system_prompt","manage_prompts","set_functional_model","edit_title_prompt","get_usage_stats","manage_memory","create_skill"]';
// ★ V9 = 十四件旧串快照（2026-09-16 技能管理工具笔升代——create_skill 改名 manage_skills，
// 件数不变）——判据语义同 V7/V8：标记 '8' 且列恰等本串（= 用户从未动过的十四件 create_skill
// 代）才升当前十四件 manage_skills 代。★ V{n} 常量语义 = 存「第 n 代检查完成时的串」作恰等
// 判据，写成新串会让存量设备升代永不命中（变更记录五百二十八节钉过的踩法）
const CONSOLE_ASSISTANT_TOOLS_V9: string =
  '["search_help","ask_user","get_time_info","set_app_preference","get_app_preference","edit_system_prompt","manage_prompts","set_functional_model","edit_title_prompt","get_usage_stats","manage_memory","create_skill","get_provider_config","get_cost_stats"]';

// 控制台助手工具 seed 检查标记键（2026-09-05 迁移复活循环修复，方案 B 持久标记——决明
// 拍板；2026-09-06 扩面升级为**代数标记**；2026-09-08 功能模型域扩面升代、同日用量统计
// 工具再升代；2026-09-13 记忆管理工具再升代、同日会话中创建技能笔再升代、同日工具补齐
// 三件笔再升代；2026-09-16 技能管理工具笔再升代）：'' = 未检查 /
// '1' = V2 时代检查完成 / '2' = 六件代检查完成 / '3' = 七件代检查完成 / '4' = 九件代（功能
// 模型域）检查完成 / '5' = 十件代（2026-09-08 用量统计工具）检查完成 / '6' = 十一件代
//（2026-09-13 记忆管理工具）检查完成 / '7' = 十二件代（2026-09-13 会话中创建技能笔）检查
// 完成 / '8' = 十四件 create_skill 代（2026-09-13 工具补齐三件笔）检查完成 / '9' = 当前代
//（十四件 manage_skills，2026-09-16 技能管理工具笔）检查完成。背景：
// 迁移判据「tools 列恰等旧串」在用户关闭某工具后**恰好落回上一代串**（剩余集合 ≠ 默认集合
// → 显式序列化产物 = 旧代串）——列值本身无法区分「从未动过」与「关闭了新工具」，每次启动
// 都会重触发迁移把关闭态复活（真机 09-05 实锤，构造序列复现）。代数标记让判据按代分流
//（'' 只认 V1、'1' 只认 V2、'2' 只认 V3、'3' 只认 V4、'4' 只认 V5、'5' 只认 V6、'6' 只认
// V7、'7' 只认 V8、'8' 只认 V9）——关闭态的恰等旧串因标记代数不符而不迁（复活循环切断点）。标记只进不退：检查完成
//（迁移或零触碰或首启插入）即推进到当前代；失败不推进（update/insert 抛错 → 函数 reject
// → 下次启动重试）。形态与
// 注册门闩照 ProviderPresetSeed 完成标记先例——本函数由 onCreate 迁移链尾发起而标记键
// persistProp 注册在 loadContent 回调，读标记前必须等注册完成，防磁盘值未加载误判重跑
export const CONSOLE_TOOLS_SEEDED_KEY: string = 'console_tools_seeded';

// 注册门闩（ProviderPresetSeed 同款）：resolve 句柄模块加载时同步捕获，notify 一次性放行
let releaseConsoleToolsGate: (() => void) | null = null;
const consoleToolsKeyRegistered: Promise<void> = new Promise<void>((resolve: () => void): void => {
  releaseConsoleToolsGate = resolve;
});

// EntryAbility 在标记键 persistProp 注册完成后调用（loadContent 回调 persistProp 区）
export function notifyConsoleToolsKeyRegistered(): void {
  if (releaseConsoleToolsGate !== null) {
    releaseConsoleToolsGate();
  }
}

// 当前助手持久键（AppStorage，EntryAbility persistProp 注册——DEFAULT_PROVIDER_KEY 同族）：
// 写入点唯一 = 助手页签（点卡切换 / 删除当前助手重置默认）；消费方 = 历史列表过滤
//（historyFilterIds）/ 新会话落行绑定 / 注入链新会话回退（ChatPromptState）
export const ACTIVE_ASSISTANT_KEY: string = 'activeAssistantId';

// 历史列表过滤口径（★2026-09-04 晚定稿：'' 统一 = 内置默认助手，跟随当前语义撤销——回退
// 2026-09-01 口径）：默认助手名下 = 显式绑定默认 + 存量未绑定行（''）；其余助手 = 自身 id
// 单值。纯函数返回纯数组字面量（坑6 族：in() 入参须非观察代理）——ChatDb.queryConversations 入参用
export function historyFilterIds(activeId: string): string[] {
  return activeId === ASSISTANT_DEFAULT_ID ? [ASSISTANT_DEFAULT_ID, ''] : [activeId];
}

// 名称/提示词长度上限（编辑页 maxLength 同值；与 PromptTemplateDb 上限对齐——有界红线：
// 提示词 = 注入上下文体积，防无界增长）
export const ASSISTANT_NAME_MAX: number = 50;
export const ASSISTANT_PROMPT_MAX: number = 2000;

export interface AssistantRow {
  id: string;
  name: string;
  prompt: string;
  createdAt: number;
  // 列表自定义序（v40，2026-09-22 助手自定义列表序）：小者在前、0 起——列表序的**唯一
  // 权威**（本笔撤除旧读侧「内置两张恒列头部」硬钉，UI 不再有任何位置特判）。回写 =
  // saveAssistantOrder 整表按卡片序赋下标；新建取 max+1 落尾。缺列/脏值不影响功能：
  // 读侧同列并列时用 createdAt 决胜，序恒确定
  sortOrder: number;
  // 模型绑定三列（v10）：providerId/modelId = 绑定的服务商与对话模型（'' = 未绑定）；
  // thinkLevel = 思考档位（'' /off/low/high/max——枚举同 AiTypes.THINKING_OPTIONS）
  providerId: string;
  modelId: string;
  thinkLevel: string;
  // 高级设定参数（v11）：采样与上下文参数 JSON 串（'' = 未配置；结构见 AiTypes
  // AssistantAdvancedParams——解析/序列化单一落点在 AiTypes，本域只存取原串）
  advancedParams: string;
  // 启用工具 id 清单（v14，2026-09-02 工具调用底层）：JSON 串（'' = 默认集合；解析/
  // 序列化单一落点在 ToolTypes.parse/serializeEnabledToolIds，本域只存取原串）
  tools: string;
  // 记忆两开关（v20，2026-09-08 记忆域）：memoryInject = 会话发送时注入记忆块 /
  // memorySink = 退出会话时整理沉淀；默认 true = 存量助手升级后默认参与（与全局
  // 总开关开 + 自动整理关默认组合叠加 → 零行为变化）
  memoryInject: boolean;
  memorySink: boolean;
  // 工具调用轮数上限（v22，2026-09-09）：0 = 不限制（由 ToolLimits.TOOL_STEP_HARD_CAP
  // 256 兜底）/ 1~32 = 该助手单次发送内工具调用轮数上限；默认 32 = 旧全局常量同值
  //（存量助手零行为变化）。换算单一来源 = ToolLimits.resolveToolStepLimit，本域只存取原值
  toolStepLimit: number;
  // 搜索结果条数（v25，2026-09-10 搜索条数助手级可调）：1~25 = 该助手的搜索单次返回条数
  //（联网搜索请求体与解析上限同源消费）；默认 5 = 旧全局常量 SEARCH_RESULT_COUNT 同值
  //（存量助手零行为变化）。值域与换算单一来源 = SearchLimits.resolveSearchResultCount，
  // 本域只存取原值
  searchResultCount: number;
  // 启用技能 id 清单（v30，2026-09-13 技能层）：JSON 串（★ 语义与 tools **刻意不同**——
  // '' = 空集合 = 默认不启用任何技能，见 SkillText 头注释）。解析/序列化单一落点 =
  // SkillText.parse/serializeEnabledSkillIds，本域只存取原串
  skills: string;
  // 记忆作用域（v35，2026-09-20 助手级记忆）：'global' 默认 = 全局记忆 = memories 表路径
  // 零改动 / 'assistant' = 助手记忆 = 注入/沉淀/检索全走 assistant_memories 里自己的库；
  // 枚举常量 MEMORY_SCOPE_* 在 MemoryDb.ets，读取非空串兜底 'global'
  memoryScope: string;
  // 启用知识库 id 清单（v38，2026-09-21 世界书知识库）：JSON 串（★ 语义与 skills 列**相同**、
  // 与 tools 列相反——'' = 空集合 = 不启用任何知识库）。解析/序列化单一落点 =
  // KnowledgeText.parse/serializeEnabledKnowledgeIds，本域只存取原串
  knowledge: string;
}

function requireStore(): relationalStore.RdbStore {
  return sharedRdbStore();
}

// 全量助手（助手页签列表 / 选助手面板 / 设置记忆页库列表；序 = **sortOrder 升序 + createdAt
// 升序决胜**（v40 起列表序单键权威，Card 序即注入序之列的兄弟实现——同形制见 MemoryDb）；
// ★ 2026-09-22 撤除「内置两张恒列头部」硬钉（原实现把内置默认/控制台助手抽出来拼到数组首，
// 缘由 = 「seed createdAt 晚于存量自建会沉底，固定序」——排序列落地后该缘由消失，且四家竞品
// 一律不置顶内置项，决明同日拍板跟进：内置两张可被用户拖到任意位置，唯一内置特权 = 禁删；
// 存量设备的可见序由 v39→v40 迁移回填复刻，升级后列表逐字不变，详见 ChatDbMigrate v40 注释）。
// 默认助手 prompt 经读时联结替换为系统提示词内容、控制台助手经读时联结替换为内置路由提示词
// ——卡面预览/面板摘要即时同步；用户手建小数据集自然有界）
export async function queryAssistants(): Promise<AssistantRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.orderByAsc('sortOrder');
  predicates.orderByAsc('createdAt');
  const result: relationalStore.ResultSet = await requireStore().query(predicates,
    ['id', 'name', 'prompt', 'createdAt', 'sortOrder', 'providerId', 'modelId', 'thinkLevel',
    'advancedParams', 'tools', 'memoryInject', 'memorySink', 'toolStepLimit', 'searchResultCount',
    'skills', 'memoryScope', 'knowledge']);
  const rows: AssistantRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        prompt: result.getString(result.getColumnIndex('prompt')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
        providerId: result.getString(result.getColumnIndex('providerId')),
        modelId: result.getString(result.getColumnIndex('modelId')),
        thinkLevel: result.getString(result.getColumnIndex('thinkLevel')),
        advancedParams: result.getString(result.getColumnIndex('advancedParams')),
        tools: result.getString(result.getColumnIndex('tools')),
        memoryInject: result.getLong(result.getColumnIndex('memoryInject')) === 1,
        memorySink: result.getLong(result.getColumnIndex('memorySink')) === 1,
        toolStepLimit: result.getLong(result.getColumnIndex('toolStepLimit')),
        searchResultCount: result.getLong(result.getColumnIndex('searchResultCount')),
        skills: result.getString(result.getColumnIndex('skills')),
        memoryScope: result.getString(result.getColumnIndex('memoryScope')) || MEMORY_SCOPE_GLOBAL,
        knowledge: result.getString(result.getColumnIndex('knowledge'))
      });
    }
  } finally {
    result.close();
  }
  const def: AssistantRow | undefined =
    rows.find((row: AssistantRow): boolean => row.id === ASSISTANT_DEFAULT_ID);
  if (def !== undefined) {
    await syncDefaultPrompt(def);
  }
  const consoleRow: AssistantRow | undefined =
    rows.find((row: AssistantRow): boolean => row.id === ASSISTANT_CONSOLE_ID);
  if (consoleRow !== undefined) {
    syncConsolePrompt(consoleRow);
  }
  return rows;
}

// 列表序持久化（2026-09-22 助手自定义列表序；saveProviderOrder / saveMemoryOrder 同形制）：
// 排序页拖拽落定后调用，ids = 该序全量 id 数组，逐行回写 sortOrder = 下标。助手是用户手建
// 小数据集（个位数行），整表回写开销可忽略；不回写 createdAt（创建时刻是事实，不改）
export async function saveAssistantOrder(ids: string[]): Promise<void> {
  for (let i = 0; i < ids.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
    predicates.equalTo('id', ids[i]);
    await requireStore().update(bucket, predicates);
  }
}

// 下一位列表序（新建助手落尾——insertProvider 同款语义：取当前最大 + 1；空表 = 0）。
// 走单列聚合查询（不调 queryAssistants——那会连带触发读时联结与全列投影，新建路径用不上）
async function nextAssistantSortOrder(): Promise<number> {
  const result: relationalStore.ResultSet =
    await requireStore().querySql('SELECT MAX(sortOrder) AS maxOrder FROM assistants');
  try {
    if (result.goToNextRow()) {
      const idx: number = result.getColumnIndex('maxOrder');
      // 空表：MAX 无行可算 = NULL（直接 getLong 的降级值不保证为 0，显式判空后给 0）
      return result.isColumnNull(idx) ? 0 : result.getLong(idx) + 1;
    }
    return 0;
  } finally {
    result.close();
  }
}

// 默认助手提示词读时联结（反馈轮 3 恒同步机制——头注释⑤）：assistants 行 prompt 列恒 ''
// 不落盘，读取时以系统提示词行内容替换——注入链（ChatPromptState.queryAssistant）与全部
// UI 展示（助手卡预览/选助手面板/编辑页只读框）自动同源；读取失败（DB 异常）保留行内值
//（'' = 无注入），不炸链路
async function syncDefaultPrompt(row: AssistantRow): Promise<AssistantRow> {
  try {
    const globalRow: PromptTemplateRow = await queryGlobalTemplate();
    row.prompt = globalRow.content;
  } catch (e) {
    // 系统提示词行查询失败——保留 ''（无注入），编辑/保存链另有 toast 呈报
  }
  return row;
}

// 控制台助手提示词读时联结（同步——联结源是进程内常量无 IO）：prompt 列恒 '' 不落盘，
// 读取时以内置路由提示词常量替换——注入链（ChatPromptState.queryAssistant）与全部 UI
// 展示（助手卡预览/选助手面板/编辑页只读框）自动同源
function syncConsolePrompt(row: AssistantRow): AssistantRow {
  row.prompt = CONSOLE_ASSISTANT_PROMPT;
  return row;
}

// 内置默认助手兜底（启动一次性，幂等——失败下次启动重试；ensurePromptGlobal 同款先例）：
// 无行才插（「默认助手」空提示词）；已存在（含用户改名/填提示词后）零触碰不覆盖
export async function ensureDefaultAssistant(): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', ASSISTANT_DEFAULT_ID);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id']);
  try {
    if (result.rowCount > 0) {
      return;
    }
  } finally {
    result.close();
  }
  const bucket: relationalStore.ValuesBucket = {
    'id': ASSISTANT_DEFAULT_ID, 'name': ASSISTANT_DEFAULT_NAME, 'prompt': '',
    'createdAt': Date.now(), 'sortOrder': await nextAssistantSortOrder()
  };
  await requireStore().insert('assistants', bucket);
}

// 内置控制台助手兜底（照 ensureDefaultAssistant 同款先例：启动一次性，幂等——失败下次启动
// 重试；无行才插〔prompt 恒 '' 读时联结常量 + tools 显式列〕）。★ 2026-09-05 设置写工具
// 增存量迁移 + ★ 同日复活循环修复（方案 B 持久标记，真机构造序列复现实锤后决明拍板）+
// ★ 2026-09-06 设置读工具扩面升级逐级迁移（RDB 逐级迁移铁律同哲学）+ ★ 2026-09-08 功能
// 模型域与用量统计工具两次扩面各升一代 + ★ 2026-09-13 记忆管理工具再升一代 + ★ 同日
// 会话中创建技能笔再升一代（V7）+ ★ 同日工具补齐三件笔再升一代（V8）+ ★ 2026-09-16
// 技能管理工具笔再升一代（V9——create_skill 改名 manage_skills，件数不变）：已存在分支判据 =
// **标记代数分流的恰等匹配**——标记
// ''（V2 时代前设备）且列恰等 V1（三件旧串）→ 升当前十四件；标记 '1'（V2 时代设备）且列恰等
// V2（四件串）→ 升当前十四件；标记 '2'（六件代设备）且列恰等 V3（六件串）→ 升当前十四件；
// 标记 '3'（七件代设备）且列恰等 V4（七件串）→ 升当前十四件；标记 '4'（九件代设备）且列恰等
// V5（九件串）→ 升当前十四件；标记 '5'（十件代设备）且列恰等 V6（十件串）→ 升当前十四件；
// 标记 '6'（十一件代设备）且列恰等 V7（十一件串）→ 升当前十四件；标记 '7'（十二件代设备）
// 且列恰等 V8（十二件串）→ 升当前十四件（2026-09-13 工具补齐三件笔）；标记 '8'（十四件
// create_skill 代设备）且列恰等 V9（十四件旧串）→ 升当前十四件 manage_skills 代
//（2026-09-16 技能管理工具笔）。恰等判据单独不
// 充分：用户关闭某工具
// 后剩余集合 ≠ 默认集合，显式序列化产物**恰好落回上一代串**——标记代数把它与「从未动过」
// 区分开（'2' 且列 = V2 = 用户显式关闭 set_app_preference 的保护态，不迁不复活）。检查完成
// 即把标记推进到当前代 '9'，此后列值任何形态都是用户显式状态，迁移永不重跑。其余值（用户
// 已自定义）零触碰不塞新工具——尊重显式选择。update/insert 抛错标记不写，下次启动重试。
// 改写走 updateAssistantTools 单列 UPDATE，其余列不碰；查询列 ['id','tools']
export async function ensureConsoleAssistant(): Promise<void> {
  await consoleToolsKeyRegistered;
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', ASSISTANT_CONSOLE_ID);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id', 'tools']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      const tools: string = result.getString(result.getColumnIndex('tools'));
      const mark: string = AppStorage.get<string>(CONSOLE_TOOLS_SEEDED_KEY) ?? '';
      if (mark === '' && tools === CONSOLE_ASSISTANT_TOOLS_V1) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V1 三件 → 十四件）');
      } else if (mark === '1' && tools === CONSOLE_ASSISTANT_TOOLS_V2) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V2 四件 → 十四件）');
      } else if (mark === '2' && tools === CONSOLE_ASSISTANT_TOOLS_V3) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V3 六件 → 十四件）');
      } else if (mark === '3' && tools === CONSOLE_ASSISTANT_TOOLS_V4) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V4 七件 → 十四件）');
      } else if (mark === '4' && tools === CONSOLE_ASSISTANT_TOOLS_V5) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V5 九件 → 十四件）');
      } else if (mark === '5' && tools === CONSOLE_ASSISTANT_TOOLS_V6) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V6 十件 → 十四件）');
      } else if (mark === '6' && tools === CONSOLE_ASSISTANT_TOOLS_V7) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V7 十一件 → 十四件）');
      } else if (mark === '7' && tools === CONSOLE_ASSISTANT_TOOLS_V8) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V8 十二件 → 十四件）');
      } else if (mark === '8' && tools === CONSOLE_ASSISTANT_TOOLS_V9) {
        await updateAssistantTools(ASSISTANT_CONSOLE_ID, CONSOLE_ASSISTANT_TOOLS);
        hilog.info(DOMAIN, TAG, '控制台助手工具 seed 迁移完成（V9 十四件 → 十四件，create_skill 并入 manage_skills）');
      }
      // 检查完成即推进标记到当前代（迁移与否）：此后 tools 列任何值均为显式状态，迁移
      // 永不重跑；update 抛错时本行不达（标记未推进，下次启动重试）
      AppStorage.setOrCreate<string>(CONSOLE_TOOLS_SEEDED_KEY, '9');
      return;
    }
  } finally {
    result.close();
  }
  const bucket: relationalStore.ValuesBucket = {
    'id': ASSISTANT_CONSOLE_ID, 'name': ASSISTANT_CONSOLE_NAME, 'prompt': '',
    'createdAt': Date.now(), 'tools': CONSOLE_ASSISTANT_TOOLS,
    'sortOrder': await nextAssistantSortOrder()
  };
  await requireStore().insert('assistants', bucket);
  AppStorage.setOrCreate<string>(CONSOLE_TOOLS_SEEDED_KEY, '9');
}

// 按 id 查助手（注入链解析用；查不到 = 已删/坏 id → null，调用方回退既有注入链）。
// ★默认助手经 syncDefaultPrompt 读时联结——返回的 prompt = 系统提示词内容；控制台助手经
// syncConsolePrompt——返回的 prompt = 内置路由提示词常量（注入链与展示共用本函数，
// 同步语义单点落位）
export async function queryAssistant(id: string): Promise<AssistantRow | null> {
  if (id === '') {
    return null;
  }
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates,
    ['id', 'name', 'prompt', 'createdAt', 'sortOrder', 'providerId', 'modelId', 'thinkLevel',
    'advancedParams', 'tools', 'memoryInject', 'memorySink', 'toolStepLimit', 'searchResultCount',
    'skills', 'memoryScope', 'knowledge']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      const row: AssistantRow = {
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        prompt: result.getString(result.getColumnIndex('prompt')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        sortOrder: result.getLong(result.getColumnIndex('sortOrder')),
        providerId: result.getString(result.getColumnIndex('providerId')),
        modelId: result.getString(result.getColumnIndex('modelId')),
        thinkLevel: result.getString(result.getColumnIndex('thinkLevel')),
        advancedParams: result.getString(result.getColumnIndex('advancedParams')),
        tools: result.getString(result.getColumnIndex('tools')),
        memoryInject: result.getLong(result.getColumnIndex('memoryInject')) === 1,
        memorySink: result.getLong(result.getColumnIndex('memorySink')) === 1,
        toolStepLimit: result.getLong(result.getColumnIndex('toolStepLimit')),
        searchResultCount: result.getLong(result.getColumnIndex('searchResultCount')),
        skills: result.getString(result.getColumnIndex('skills')),
        memoryScope: result.getString(result.getColumnIndex('memoryScope')) || MEMORY_SCOPE_GLOBAL,
        knowledge: result.getString(result.getColumnIndex('knowledge'))
      };
      if (row.id === ASSISTANT_DEFAULT_ID) {
        return syncDefaultPrompt(row);
      }
      if (row.id === ASSISTANT_CONSOLE_ID) {
        return syncConsolePrompt(row);
      }
      return row;
    }
    return null;
  } finally {
    result.close();
  }
}

// 新增助手（名称非空由调用方校验；列表序 = 当前最大 + 1 落尾——insertProvider 同款，
// 新建的助手出现在列表末尾，用户可拖到任意位置）
export async function insertAssistant(name: string, prompt: string): Promise<AssistantRow> {
  const sortOrder: number = await nextAssistantSortOrder();
  const row: AssistantRow = {
    id: nextMessageId('asst'),
    name: name,
    prompt: prompt,
    createdAt: Date.now(),
    sortOrder: sortOrder,
    providerId: '',
    modelId: '',
    thinkLevel: '',
    advancedParams: '',
    tools: '',
    memoryInject: true,
    memorySink: true,
    toolStepLimit: TOOL_STEP_LIMIT_DEFAULT,
    searchResultCount: SEARCH_RESULT_COUNT_DEFAULT,
    skills: '',
    memoryScope: MEMORY_SCOPE_GLOBAL,
    knowledge: ''
  };
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'name': row.name, 'prompt': row.prompt, 'createdAt': row.createdAt,
    'sortOrder': sortOrder,
    'providerId': '', 'modelId': '', 'thinkLevel': '', 'advancedParams': '', 'tools': '',
    'memoryInject': 1, 'memorySink': 1, 'toolStepLimit': TOOL_STEP_LIMIT_DEFAULT,
    'searchResultCount': SEARCH_RESULT_COUNT_DEFAULT, 'skills': '',
    'memoryScope': MEMORY_SCOPE_GLOBAL, 'knowledge': ''
  };
  await requireStore().insert('assistants', bucket);
  return row;
}

// 更新助手名称（2026-09-01 编辑页分区化：名称与提示词分页编辑，各走单列 UPDATE——Key 池
// label 改名同款零堆积）。0 行 throw（updateTemplate 同款 P0-1 假成功防御：目标行不存在时
// 调用方 toast「已保存」= 撒谎）
export async function updateAssistantName(id: string, name: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'name': name };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手提示词（提示词二级页「保存」；引用跟随——所有引用会话下次发送自动用新版。
// 0 行 throw 同上）
export async function updateAssistantPrompt(id: string, prompt: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'prompt': prompt };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手模型绑定（模型设置页选择落库；providerId+modelId 一个语义单元同批 UPDATE——
// 0 行 throw 同 updateAssistantName）。选择即时落库不经保存键（重命名同款口径）
export async function updateAssistantModelBinding(id: string, providerId: string,
  modelId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'providerId': providerId, 'modelId': modelId };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手思考档位（模型设置页菜单选择落库；值域 = AiTypes.THINKING_OPTIONS，'' = 默认
// 不传。0 行 throw 同上）
export async function updateAssistantThinkLevel(id: string, level: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'thinkLevel': level };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手高级设定参数（采样/上下文三级页返回时统一落库；入参 = 序列化后 JSON 串，
// 序列化在调用方完成〔AiTypes.serializeAssistantAdvancedParams——'' = 全默认〕。0 行
// throw 同上）
export async function updateAssistantAdvancedParams(id: string, params: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'advancedParams': params };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手启用工具清单（工具页签开关切换落库；入参 = 序列化后 JSON 串，序列化在调用方
// 完成〔ToolTypes.serializeEnabledToolIds——默认集合存 ''〕。0 行 throw 同上）
export async function updateAssistantTools(id: string, tools: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'tools': tools };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手记忆两开关（2026-09-08 记忆域 v20 两列；助手记忆页开关行即时落库——注入/
// 沉淀一个语义单元同批 UPDATE；0 行 throw 同上）
export async function updateAssistantMemoryFlags(id: string, memoryInject: boolean,
  memorySink: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket =
    { 'memoryInject': memoryInject ? 1 : 0, 'memorySink': memorySink ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手记忆作用域（v35，2026-09-20 助手级记忆：AssistantMemoryPage 分段胶囊切换即时
// 落库——'global'/'assistant' 枚举校验在调用方，本层直存。0 行 throw 同上）
export async function updateAssistantMemoryScope(id: string, scope: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'memoryScope': scope };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手工具调用轮数上限（v22，2026-09-09 上限可设置笔：工具调用页返回时落库——滑轨
// 拖动全程只改内存态，返回统一写一次，避免拖动过程高频写库；0 = 不限制语义见 ToolLimits）。
// 0 行 throw 同上
export async function updateAssistantToolStepLimit(id: string, limit: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'toolStepLimit': limit };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手搜索结果条数（v25，2026-09-10 搜索条数助手级可调：工具调用页返回时落库——滑轨
// 拖动全程只改内存态，返回统一写一次，避免拖动过程高频写库；值域 1~25 语义见 SearchLimits）。
// 0 行 throw 同上
export async function updateAssistantSearchResultCount(id: string, count: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'searchResultCount': count };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手启用技能清单（v30，2026-09-13 技能层：助手技能页 Toggle 即时落库——写入值 =
// SkillText.serializeEnabledSkillIds 产物，'' = 空集合 = 不启用任何技能；启用的第 11 个
// 在页面侧被 SKILL_ENABLED_MAX 拦截，本层不做二次判定（两处判定 = 两处漂移面））。
// 0 行 throw 同上
export async function updateAssistantSkills(id: string, skills: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'skills': skills };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 更新助手启用知识库清单（v38，2026-09-21 世界书知识库：助手知识库页 Toggle 即时落库——
// 写入值 = KnowledgeText.serializeEnabledKnowledgeIds 产物，'' = 空集合 = 不启用任何知识库；
// 启用的第 11 个在页面侧被 KNOWLEDGE_ENABLED_MAX 拦截，本层不做二次判定（两处判定 = 两处
// 漂移面，与 updateAssistantSkills 同口径）。0 行 throw 同上）
export async function updateAssistantKnowledge(id: string, knowledge: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'knowledge': knowledge };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('id', id);
  const affected: number = await requireStore().update(bucket, predicates);
  if (affected === 0) {
    throw new Error('目标助手行不存在（已被删除），保存未生效');
  }
}

// 级联清绑定列（清删机制——ProviderDb.deleteProvider 事务内调用）：该服务商绑定全清
// （providerId/modelId/thinkLevel 三列一起归空——强度档位离开原服务商无意义，一并复位）
export async function clearAssistantBindingByProvider(providerId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket =
    { 'providerId': '', 'modelId': '', 'thinkLevel': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('providerId', providerId);
  await requireStore().update(bucket, predicates);
}

// 级联清绑定列（ProviderDb.deleteModel 调用）：只清「绑定到该服务商该模型」的助手行
//（同服务商换绑其他模型不受影响）；三列一起归空语义同上
export async function clearAssistantBindingByModel(providerId: string, modelId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket =
    { 'providerId': '', 'modelId': '', 'thinkLevel': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  predicates.equalTo('providerId', providerId);
  predicates.equalTo('modelId', modelId);
  await requireStore().update(bucket, predicates);
}

// 助手名下会话数（删除确认文案「名下 N 个会话」用；'' 行 = 未显式绑定 = 默认助手名下——
// 只查显式绑定值，删助手不级联未绑定会话，默认助手禁删）。★ 与 queryAssistantConversationCounts
// 的分工（2026-09-20 助手页卡面「会话」chip 用）见其注释——两函数口径刻意不同，禁合并
export async function queryAssistantConversationCount(id: string): Promise<number> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('assistantId', id);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id']);
  try {
    return result.rowCount;
  } finally {
    result.close();
  }
}

// 全助手会话计数（assistantId → 行数；助手页卡面「会话」chip 消费——一条 GROUP BY 免逐助手
// 查询循环，形态照 ProviderDb.queryProviderModelCounts）。★ 与 queryAssistantConversationCount
// 的口径分工（两处刻意不同，禁合并重构）：本函数回**原始分桶**（键 = conversations.assistantId
// 原值，含 '' 未绑定桶），归并交调用方按 historyFilterIds 做——默认助手名下 = 显式绑定 + ''
// 存量未绑定行（与历史列表过滤同口径，卡面数与用户点进对话页签看到的条数一致）；上函数回
// **单助手显式绑定行数**（删助手级联预检——级联只删显式绑定行，未绑定会话不随删，故两处
// 数字在默认助手上本就不同且都正确）。querySql 直查（RdbPredicates 无聚合能力），
// ResultSet 用完 close
export async function queryAssistantConversationCounts(): Promise<Map<string, number>> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT assistantId, COUNT(*) AS cnt FROM conversations GROUP BY assistantId');
  const counts: Map<string, number> = new Map();
  try {
    while (result.goToNextRow()) {
      counts.set(result.getString(result.getColumnIndex('assistantId')),
        result.getLong(result.getColumnIndex('cnt')));
    }
  } finally {
    result.close();
  }
  return counts;
}

// 删除助手 = 级联删除（2026-09-01 会话绑定改造，拍板 = RikkaHub 删助手同款硬级联无软
// 删除；内置默认助手守卫禁删——UI 侧本就不渲染删除键，此为兜底）：同事务级联——
// message_attachments 附件行（v23）→ messages（in 名下会话集）→ token_usage_events
//（2026-09-09 附件落盘笔同笔收口决明拍板：与 deleteConversations 口径④一致——删助手后
// 统计页不得残留已删会话用量）→ conversations → assistants 行，任一失败 rollBack 不半删
//（P0-1，deleteConversations 同款姿势扩一家；会话 id 集自 ResultSet 逐条收集 = 纯数组，
// 坑6 族无代理暴露）。附件文件本体删除在 commit 之后（best-effort，回滚不得已删文件）。
// **级联铁律：任何新增「删 messages」路径，必须在同函数同事务内删附件行**（全仓删
// messages 落点 = 本函数 + ChatDb.deleteConversations 两处）。返回级联删除的会话数（toast
// 呈报用）；「删除的是当前助手 → active 键重置默认 + 历史列表重拉广播」在调用方编排
//（AssistantPage.deletePending）
export async function deleteAssistantCascade(id: string): Promise<number> {
  if (id === ASSISTANT_DEFAULT_ID || id === ASSISTANT_CONSOLE_ID) {
    return -1;
  }
  const db: relationalStore.RdbStore = requireStore();
  const refPredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('conversations');
  refPredicates.equalTo('assistantId', id);
  const refResult: relationalStore.ResultSet = await db.query(refPredicates, ['id']);
  const convIds: string[] = [];
  try {
    while (refResult.goToNextRow()) {
      convIds.push(refResult.getString(refResult.getColumnIndex('id')));
    }
  } finally {
    refResult.close();
  }
  db.beginTransaction();
  try {
    let attachPaths: string[] = [];
    if (convIds.length > 0) {
      // 附件行级联（v23）：函数内先 SELECT 收集 localPath 再删行；文件 I/O 在 commit 后
      attachPaths = await deleteAttachmentsForConversations(db, convIds);
      const msgPredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('messages');
      msgPredicates.in('conversationId', convIds);
      await db.delete(msgPredicates);
      // 用量账本级联（2026-09-09 同笔收口）：名下会话的用量事件一并删——统计页只反映
      // 现存会话（deleteConversations 口径④同款，此前漏删 = 删助手后统计页仍显示已删
      // 会话用量）
      const usagePredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('token_usage_events');
      usagePredicates.in('conversationId', convIds);
      await db.delete(usagePredicates);
      const convPredicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('conversations');
      convPredicates.in('id', convIds);
      await db.delete(convPredicates);
    }
    // 记忆归属级联置空（2026-09-08 记忆域）：该助手沉淀的记忆条目保留（跨会话资产），
    // assistantId 归空去标注——与既有级联同事务口径（clearAssistantBinding 同款调用形态）
    await clearMemoryAssistantRef(id);
    // 助手级记忆库级联删行（2026-09-20 助手级记忆 v35）：库跟着人走（openers 列「随助手行
    // 生命周期级联删」同口径），与全局库置空保留的跨会话资产口径刻意不同——两库语义分离
    await deleteAssistantMemoriesOfAssistant(id);
    // 记忆优化历史快照级联删（2026-09-22 记忆优化历史）：快照是本地后悔药不是跨会话资产
    //（同 assistant_memories 口径——库跟着人走，不置空保留）；不删 = 孤儿行无界堆积
    await deleteMemorySnapshotsOfAssistant(id);
    const delPredicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('assistants');
    delPredicates.equalTo('id', id);
    await db.delete(delPredicates);
    db.commit();
    removeAttachmentFiles(attachPaths); // best-effort：失败留启动收敛自愈
    return convIds.length;
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// 会话助手引用（conversations.assistantId；★2026-09-04 晚定稿：'' = 未显式绑定 = 默认助手
// 名下口径——「跟随当前」语义撤销，解析与显示行 '' 均按内置默认助手，见 ChatPromptState）。
// ★ 返回三态（2026-09-01 会话绑定改造）：null = 会话行不存在（懒创建新会话——注入链/面板
// 据此走有效归属 = 面板覆盖 ?? 当前助手 ?? 默认）；'' = 行在但未显式绑定；非 '' = 已绑定助手 id
export async function queryConversationAssistantId(conversationId: string): Promise<string | null> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['assistantId']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return result.getString(result.getColumnIndex('assistantId'));
    }
    return null;
  } finally {
    result.close();
  }
}

export async function updateConversationAssistantId(conversationId: string,
  assistantId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'assistantId': assistantId };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  await requireStore().update(bucket, predicates);
}
