// 建表 SQL 常量域（2026-09-23 上下文压缩笔自 ChatDbMigrate.ets 域级最小拆分——该件剔头
// 1189 行已越 1200 硬线且技术债务清单早已按候选缝「SQL 建表常量整块外迁」建档，本笔是
// 压缩摘要在该域的实质增量，按宪法「单文件规模上限」条先按建档缝拆再落改动）：
// 全部表与索引的 CREATE 语句常量单一来源在本文件，**新装执行与迁移分支仍在 ChatDbMigrate**
// （ensureSchema / migrateSchema 依次引用本件常量）——本文件零函数零 import，纯常量资产；
// 各列语义与版本沿革的权威注释 = ChatDbMigrate.ets 头部版本史，块内注释只留列义速查并
// 回指该处。断言面注意：assert-store-consistency 71/143/171 组读建表 SQL 文本的判据已
// 随本笔回指本文件。
// ★ messages 表 v42 起含 coversToSeq 列（压缩摘要行覆盖边界，详见 ChatDbMigrate v42
//   版本注释）；列位置 = variant_active 与 seq 之间（v46 起建表尾段 = 图身份五列，
//   v61 起末列 = quote_text，v64 起末列 = server_tools——143 ⑨ 钉按列次序关系判，
//   收尾形态随合法加列演进）。
export const SQL_CREATE_PROMPT_TEMPLATES: string = 'CREATE TABLE IF NOT EXISTS prompt_templates (' +
  'id TEXT PRIMARY KEY, name TEXT NOT NULL, content TEXT NOT NULL DEFAULT \'\', ' +
  'isGlobal INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL, ' +
  'injectRole TEXT NOT NULL DEFAULT \'system\', injectPosition TEXT NOT NULL DEFAULT \'head\', ' +
  'injectDepth INTEGER NOT NULL DEFAULT 0)';

// v46（2026-09-26 消息架构整合笔2，任务书-消息架构整合笔2-分支存储与兼容准备-20260926）
// conversations 补两列——activeBranchId = 当前选择分支的持久真源（空串 = 未启用图，旧格式
// 会话恒空串，读侧按 migrateState 判定）；migrateState = 会话格式态（★ 2026-09-26 旧会话
// 墓碑笔冻结两值 graph/legacy，枚举 = MessageBranchDb.CONV_STATE_*，判据 =
// ChatContextSource.conversationWritableRoute）。两列均无数据
// 回填（DEFAULT 即 legacy 存量语义）。★ 注释置声明前防字面量提取器误吸引号词
//（db-chain-check 场景 D 实锤——拼接体内注释含英文引号词会被当 SQL 片段）。
// ★ v66（2026-11-17 整体退役加密会话笔）：locked 列退役为**墓碑**——加密会话功能整体撤除
//（菜单/侧滑键/锁标/进入门禁/生物识别偏好/权限声明全链退役），列定义保留不删（建表 SQL 与
// 存量库结构零变化，免重建表与降级成本），产品码零读写；存量 locked=1 由 v66 迁移一次性清零
//（ChatDbMigrate 同级注释）。新装与存量库该列恒 0，勿再接回任何读写。
export const SQL_CREATE_CONVERSATIONS: string = 'CREATE TABLE IF NOT EXISTS conversations (' +
  'id TEXT PRIMARY KEY, title TEXT NOT NULL, providerId TEXT NOT NULL DEFAULT \'\', ' +
  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, ' +
  'promptId TEXT NOT NULL DEFAULT \'\', assistantId TEXT NOT NULL DEFAULT \'\', ' +
  'locked INTEGER NOT NULL DEFAULT 0, titleSource TEXT NOT NULL DEFAULT \'\', ' +
  'favorite INTEGER NOT NULL DEFAULT 0, modelProviderId TEXT NOT NULL DEFAULT \'\', ' +
  'modelId TEXT NOT NULL DEFAULT \'\', webSearchOverride TEXT NOT NULL DEFAULT \'\', ' +
  'suggestions TEXT NOT NULL DEFAULT \'\', ' +
  'activeBranchId TEXT NOT NULL DEFAULT \'\', ' +
  'migrateState TEXT NOT NULL DEFAULT \'legacy\')';
// v46 图节点身份五列（图身份——正文仍在 messages 不另建第二份正文仓；legacy 行五列落
// 默认值 = 零行为变化，图语义只在 graph 会话消费。写空不回填、不改既有约束——J7「存量值
// 冻结不再维护、不重建表改约束」）：parentMessageId = 父节点链接（分支树的边；根节点
// NULL——列有意无约束，与 seq/coversToSeq 同理由：NULL 表达「根」语义，NOT NULL 会把根行
// 表达成假父）；runId = 产出本节点的运行（generation_runs.id 外键语义无约束弱链；legacy
// 行空串）；ownerAssistantId = 归属助手（空串 = 无绑定，J10 词表同源）；stepIndex = run 内
// 步序（工具续轮步进；NULL = 未编号）；origin = 节点来源语义（空串 = legacy/未标；值域
// 常量 ORIGIN_* 在 MessageBranchDb——本域只存取原串）。
// v61（2026-10-21 方案-引用功能全链路 U-C）：quote_text = 用户消息的引用全文快照
//（NULL = 无引用；写入唯一点 = 发送链 prepareRun bucket 条件写键——不写键落 NULL；
// 消费 = 读窗投影回放与 fork/图快照保真；语义与迁移判据见 ChatDbMigrate v61 版本注释）。
// 列有意无约束（无语义 = NULL，与 parentMessageId/seq 同理由）。注释置声明前（防字面量
// 提取器误吸引号词，workspace_files 同款口径）
// v64（2026-11-14 DS 全家桶接入批 S2）：server_tools = assistant 行的 DeepSeek 服务端工具
// 原样 JSON 串（{"server_tool_calls":…,"annotations":…} 官方末帧两字段合体——回传保真禁
// 截断禁重排，signature 超限腰斩 = 回传 400）；NULL = 非官方档轮/无服务端步骤。写入点 =
// 轮收口（终答 GraphFinishInput.serverTools / 中间轮提交口从 stampTarget 读）经
// MessageBranchDb.writeNodeServerTools 条件写键；消费 = 回放投影（chatMessagesFromRows）→
// 请求回传（buildRequestHistory → composeOpenAiBody server_tool_calls）。列有意无约束
//（无语义 = NULL，与 quote_text 同理由）。注释置声明前（防字面量提取器误吸引号词）
export const SQL_CREATE_MESSAGES: string = 'CREATE TABLE IF NOT EXISTS messages (' +
  'id TEXT PRIMARY KEY, conversationId TEXT NOT NULL, role TEXT NOT NULL, ' +
  'content TEXT NOT NULL, reasoning TEXT NOT NULL DEFAULT \'\', status TEXT NOT NULL, ' +
  'createdAt INTEGER NOT NULL, variants TEXT NOT NULL DEFAULT \'\', ' +
  'variant_active INTEGER NOT NULL DEFAULT 0, ' +
  // v42：coversToSeq = 压缩摘要行（role 为 summary）的覆盖边界——本条摘要覆盖到的最大
  // seq（含）；非摘要行恒 NULL。列有意无约束：存量行与旧备份导回行天然落 NULL = 无摘要
  // 语义（与 seq 列同款无约束理由，见 ChatDbMigrate v37/v42 版本注释）
  'coversToSeq INTEGER DEFAULT NULL, ' +
  // v37：seq = 会话内 0 起显式序号（无约束理由与回填规则见 ChatDbMigrate v37 版本注释）
  'seq INTEGER DEFAULT NULL, ' +
  'parentMessageId TEXT DEFAULT NULL, ' +
  'runId TEXT NOT NULL DEFAULT \'\', ' +
  'ownerAssistantId TEXT NOT NULL DEFAULT \'\', ' +
  'stepIndex INTEGER DEFAULT NULL, ' +
  'origin TEXT NOT NULL DEFAULT \'\', ' +
  'quote_text TEXT DEFAULT NULL, ' +
  'server_tools TEXT DEFAULT NULL)';
// providers v2（2026-08-30 服务商管理域接线）：原 v1 四列保留（model/remark 两列自 v2 起
// 停写——模型清单迁 provider_models 表、remark 无消费方；列不删 = 只加不改红线），新增
// enabled（启用开关，停用不参与聊天连接解析）/ sortOrder（列表拖拽排序，小者在前）。
// v12（2026-09-01 Anthropic 提示缓存，任务书-Anthropic提示缓存cache_control）：providers 补
// prompt_cache_enabled / prompt_cache_ttl 两列——开关默认关（写入 1.25× 计费）+ TTL 官方
// 两档 '5m'|'1h'；仅 anthropic 协议消费，compose 断点落点与官方依据见 RequestCompose 头注释
// v13（2026-09-02 自定义 Body，RikkaHub 自定义请求体对齐）：providers 补 body_overrides
// （请求体顶层键覆盖 JSON 串 [{k,v}]——k = 顶层键名，v = 合法 JSON 值文本（发送时
// JSON.parse 后覆盖/追加到组装完成的请求体根对象）；序列化语义同 headers 列——复用
// serializeHeaderPairs，空 k/v 行丢弃、空数组 = ''；入库侧校验 v 合法 JSON——非法拦截
// 保存 P0-1 不静默；四协议统一 merge 落点 = ChatStreamBase.start（协议无关））
// v3（2026-08-30 余额查询链）：balance_* 八列——enabled（总开关）/ base_url·path（专用
// 端点，空 = 回退服务 baseUrl）/ result_path·currency_path（响应点路径）/ currency（币种
// 兜底值，点路径未取到时用）/ key（专用密钥，空 = 回退聊天密钥；明文列——任务书 98461a2
// 拍板形态）/ last_text（上次查询结果文本，重启保留）
// v4（2026-08-30 多 Key 池 + 三协议）：protocol（'openai' | 'anthropic' | 'gemini'，
// 常量表在 AiTypes.ets；默认 openai = 存量行为不变）+ headers（自定义请求头 JSON 串，
// 元素 [{k,v}]，发送前逐条追加且允许覆盖内置头；空串 = 无）
// v5（2026-08-30 OpenAI Responses 适配）：endpoint（OpenAI 族接口形态：'chat' 默认 =
// /chat/completions；'responses' = /v1/responses——仅对 openai 有意义，a/g 恒 'chat'；
// 常量表 ENDPOINT_* 在 AiTypes.ets）
// v32（2026-09-17 取钥方式）：key_pick_mode（'rotate' 默认 = 按池内卡片顺序轮换，存量行为
// 不变；'random' = 每次发送随机挑起始支；常量表 KEY_PICK_* 在 ProviderKeyDb.ets，消费 =
// 发送链取钥起始位选择——只影响发请求前选哪支密钥，协议链路零触碰）
// v52（2026-10-04 AI 配置服务商笔，任务书-AI配置服务商与安全输入-20261004）：builtin
//（内置服务商标记，1 = 内置 = 不可删只能停用——数据层 deleteProvider 硬拦截 + 列表卡菜单
// 隐藏删除项 + AI 管理工具拒绝三层防线；DEFAULT 0 = 用户新建与导入行恒非内置）。存量回填
// 判据与 12 组历史快照字面量见 ChatDbMigrate v52 迁移分支；seed 侧由 ProviderPresetSeed
// 随行一步插入 true
export const SQL_CREATE_PROVIDERS: string = 'CREATE TABLE IF NOT EXISTS providers (' +
  'id TEXT PRIMARY KEY, name TEXT NOT NULL, baseUrl TEXT NOT NULL, model TEXT NOT NULL, ' +
  'remark TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL, ' +
  'enabled INTEGER NOT NULL DEFAULT 1, sortOrder INTEGER NOT NULL DEFAULT 0, ' +
  'balance_enabled INTEGER NOT NULL DEFAULT 0, balance_base_url TEXT NOT NULL DEFAULT \'\', ' +
  'balance_path TEXT NOT NULL DEFAULT \'\', balance_result_path TEXT NOT NULL DEFAULT \'\', ' +
  'balance_currency TEXT NOT NULL DEFAULT \'\', balance_currency_path TEXT NOT NULL DEFAULT \'\', ' +
  'balance_key TEXT NOT NULL DEFAULT \'\', balance_last_text TEXT NOT NULL DEFAULT \'\', ' +
  'balance_headers TEXT NOT NULL DEFAULT \'\', ' +
  'protocol TEXT NOT NULL DEFAULT \'openai\', headers TEXT NOT NULL DEFAULT \'\', ' +
  'endpoint TEXT NOT NULL DEFAULT \'chat\', ' +
  'prompt_cache_enabled INTEGER NOT NULL DEFAULT 0, ' +
  'prompt_cache_ttl TEXT NOT NULL DEFAULT \'5m\', ' +
  'body_overrides TEXT NOT NULL DEFAULT \'\', ' +
  'key_pick_mode TEXT NOT NULL DEFAULT \'rotate\', ' +
  'builtin INTEGER NOT NULL DEFAULT 0)';
// provider_models v2 新建：服务商的模型清单（一行一个模型）。kind = 'chat'（对话）/
// 'embedding'（向量）；caps = 能力码逗号串（'tool,reason,web,vision,image' 子集，码表与
// UI 文案映射在 ProviderDb MODEL_CAP_* 常量）；name 为空时 UI 兜底显示 modelId；
// v3 加 enabled（模型级启停，停用不进选择面板与连接解析）；
// v15（2026-09-03 Cube 吸收 A1 能力注册表）加 caps_user_modified（能力派生/覆盖标志：
// 0 = 未手改——展示与消费走 effectiveCaps 读时按模型名派生〔ModelRegistry，规则升级
// 自动跟随，派生值不落库〕；1 = 用户手改固化——caps 列原样生效含显式全不勾）；
// v21（2026-09-08 模型选择半模态优化）加 favorite（模型收藏标记，语义见 ChatDbMigrate v21 注释）；
// v27（2026-09-10 费用估计）加 price_config（价格 JSON 串，'' = 未配置；单位 =
// 元/百万 tokens，字段结构与解析/序列化单一来源 = CostStatsCalc.ets——本注释不复制结构
// 防双源漂移）；
// v33（2026-09-17 模型上下文窗口）加 context_window（token 数，0 = 未配置 = 跟随内置
// 参考值/非 0 = 用户覆盖；语义见 ChatDbMigrate v33 版本注释）
export const SQL_CREATE_PROVIDER_MODELS: string = 'CREATE TABLE IF NOT EXISTS provider_models (' +
  'id TEXT PRIMARY KEY, providerId TEXT NOT NULL, modelId TEXT NOT NULL, ' +
  'name TEXT NOT NULL DEFAULT \'\', kind TEXT NOT NULL DEFAULT \'chat\', ' +
  'caps TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL, ' +
  'enabled INTEGER NOT NULL DEFAULT 1, ' +
  'caps_user_modified INTEGER NOT NULL DEFAULT 0, ' +
  'favorite INTEGER NOT NULL DEFAULT 0, ' +
  'price_config TEXT NOT NULL DEFAULT \'\', ' +
  'context_window INTEGER NOT NULL DEFAULT 0)';
// provider_keys v4 新建（多 Key 池）：一行一个 key 条目。★安全红线：key 明文禁落 DB——
// 本表只存元数据（label 掩码显示名/启停/排序），明文在 Asset（条目名 providerId+'/'+keyId，
// 见 KeyStore.ets）；label 自动编号「Key N」不可改；sortOrder = 池内取钥顺序（小者在前）
export const SQL_CREATE_PROVIDER_KEYS: string = 'CREATE TABLE IF NOT EXISTS provider_keys (' +
  'id TEXT PRIMARY KEY, providerId TEXT NOT NULL, label TEXT NOT NULL DEFAULT \'\', ' +
  'enabled INTEGER NOT NULL DEFAULT 1, sortOrder INTEGER NOT NULL DEFAULT 0, ' +
  'createdAt INTEGER NOT NULL)';
// assistants v9 新建（2026-09-01 助手域，CRUD 在 AssistantDb.ets）：一行一个助手。
// 字段极简 = 只收 aicontrol 已支持能力（名称/提示词）；RikkaHub 助手的采样参数/绑定模型/
// 记忆/工具/正则/快捷短语等暂不支持的能力不建列（结构即能力边界，不显示不记录进 DB）。
// v10（2026-09-01 模型绑定）补三列：providerId/modelId（助手级绑定，空 = 未绑定）+
// thinkLevel（思考档位，'' = 默认不传；枚举同 AiTypes.THINKING_OPTIONS）。
// v11（2026-09-01 高级设定）补 advancedParams：采样与上下文参数 JSON 串（'' = 未配置；
// 结构见 ChatDbMigrate v11 版本注释）
// v14（2026-09-02 工具调用底层）补 tools：启用工具 id 清单 JSON 串（'' = 默认集合 =
// 内置 defaultEnabled 项；解析/序列化单一落点 ToolTypes.parse/serializeEnabledToolIds；
// 删助手整行级联同既有，无跨表引用）
// v12 → v13（2026-09-02 自定义 Body）
// v20（2026-09-08 记忆域）补 memoryInject/memorySink：助手级两开关（注入/沉淀），默认 1
// 开 = 存量助手升级后默认参与（与全局总开关开 + 自动整理关默认叠加 → 零行为变化）
// v22（2026-09-09 工具轮上限）补 toolStepLimit：助手级工具调用轮数上限，默认 32 = 旧全局
// 常量同值（0 = 不限制，语义与 256 硬顶见 ChatDbMigrate v22 版本注释）
// v25（2026-09-10 搜索结果条数）补 searchResultCount：助手级单次搜索返回条数，默认 5 = 旧
// 全局常量 SEARCH_RESULT_COUNT 同值（值域 1~25，语义见 ChatDbMigrate v25 版本注释）
// v30（2026-09-13 技能层）补 skills：助手启用技能 id 清单 JSON 串（★ 语义与 tools 列**刻意
// 不同**——''（含坏 JSON） = 空集合 = **默认不启用任何技能**，不是 tools 的「默认集合」；
// 启用口径 = 全局技能库 + 本列显式勾选，新装与新助手零启用零注入零声明，请求逐字节同无
// 技能版）。解析/序列化单一落点 = SkillText.parseEnabledSkillIds / serializeEnabledSkillIds
//（另立一份而**禁复用** tools 函数——两列语义相反，复用即等着被后人按 tools 口径改坏）；
// 本域只存取原串
// v35（2026-09-20 助手级记忆）补 memoryScope：记忆作用域二选一（'global' 默认 = 全局记忆
// = 存量行为原样；'assistant' = 助手记忆 = 注入/沉淀/检索全走 assistant_memories 里自己
// 的库）；枚举常量 MEMORY_SCOPE_* 在 MemoryDb.ets。**禁复用 skills/tools 的解析函数**——
// 本列是受限枚举非 JSON 串，读写单落点 = AssistantDb（非空串兜底 'global'）
// v38（2026-09-21 世界书知识库）补 knowledge：助手启用的知识库 id 清单 JSON 串（★ 语义与
// skills 列**相同**、与 tools 列相反——''（含坏 JSON） = 空集合 = 不启用任何知识库；启用
// 口径 = 全局知识库 + 本列显式勾选，存量助手升级后零声明零注入）。解析/序列化单一落点 =
// KnowledgeText.parseEnabledKnowledgeIds / serializeEnabledKnowledgeIds
//（三列语义各不相同，**禁合并复用**任一既有解析函数——同 skills 列当年立的口径）
// v45（2026-09-24 助手头像）补 avatar：头像编码原串（'' = 默认首字圆底；'text:<内容>' =
// 文字/表情 ≤2 码点；'image:<uri>' = 图片——本地 file:// 或网络 http(s)://，两形态同一
// kind）。解析/序列化/文件命名/清理单一落点 = common/AvatarSpec.ets，本域只存取原串；
// 脏值渲染兜底视同默认。沙箱图片文件不进备份（ExportImport 按表整搬，列随行、文件不随行）
// ★ 墓碑列（2026-09-27 工具运行参数全局化笔，决明拍板「只在设置页全局控制」）：toolStepLimit
//（v22）与 searchResultCount（v25）两列自本笔起**退役**——两值改由全局偏好键
// prefToolStepLimit / prefSearchResultCount 承载（全助手一份，控制面 = 设置页工具调用页轮数卡
// 与联网搜索页条数卡〔条数卡同日第二笔随联网域搬家〕），
// 本域（AssistantDb）与发送链已断全部读写。列保留不删 = 有意选择：零迁移零风险、旧备份回填
// 天然兼容（导入按 PRAGMA 现存列过滤）、用户原设值不销毁；**勿新增任何读写点**（要复活按
// 「全局 vs 助手级」重新论证，勿直接拿本两列接回去）
// v51（2026-10-04 世界书关键词触发笔）补 knowledgeAutoInject：助手级「关键词自动注入」
// 开关（默认 **0 关**——与 memoryInject/memorySink 的 DEFAULT 1 不同，本开关拍板默认关：
// 存量助手升级后不自动注入，请求逐字节同升级前；用户在助手知识库页显式打开才参与）。
// 语义与读写规矩见 AssistantDb.AssistantRow 对应注释
// v59（2026-10-19 方案-MCP页施工方案 B2）补 mcpServers：助手勾选的 MCP 服务器 id 清单
// JSON 串（★ 语义照 skills〔v30〕/ knowledge〔v38〕第四例——''（含坏 JSON） = 空集合 =
// 不启用任何 MCP 服务器；启用口径 = 全局服务器库〔mcp_servers 表 enabled 行〕∩ 本列显式
// 勾选）。解析/序列化单一落点 = McpText.parseEnabledMcpServerIds / serializeEnabledMcpServerIds
//（另立一份而**禁复用** skills/knowledge/tools 任何既有解析函数——三列语义各异是当年立的
// 口径，本域只存取原串）。删服务器时联动剔列（McpDb.clearMcpServerRefInAssistants，
// SkillDb 联动清列同形）
export const SQL_CREATE_ASSISTANTS: string = 'CREATE TABLE IF NOT EXISTS assistants (' +
  'id TEXT PRIMARY KEY, name TEXT NOT NULL, prompt TEXT NOT NULL DEFAULT \'\', ' +
  'createdAt INTEGER NOT NULL, providerId TEXT NOT NULL DEFAULT \'\', ' +
  'modelId TEXT NOT NULL DEFAULT \'\', thinkLevel TEXT NOT NULL DEFAULT \'\', ' +
  'advancedParams TEXT NOT NULL DEFAULT \'\', tools TEXT NOT NULL DEFAULT \'\', ' +
  'memoryInject INTEGER NOT NULL DEFAULT 1, memorySink INTEGER NOT NULL DEFAULT 1, ' +
  'toolStepLimit INTEGER NOT NULL DEFAULT 32, ' +
  'searchResultCount INTEGER NOT NULL DEFAULT 5, ' +
    'skills TEXT NOT NULL DEFAULT \'\', ' +
    'openers TEXT NOT NULL DEFAULT \'\', ' +
    'memoryScope TEXT NOT NULL DEFAULT \'global\', ' +
    'knowledge TEXT NOT NULL DEFAULT \'\', ' +
    'sortOrder INTEGER NOT NULL DEFAULT 0, ' +
    'avatar TEXT NOT NULL DEFAULT \'\', ' +
    'knowledgeAutoInject INTEGER NOT NULL DEFAULT 0, ' +
    'mcpServers TEXT NOT NULL DEFAULT \'\')';
// skills v30 新建（2026-09-13 技能层，CRUD 在 SkillDb.ets）：一行一件技能。name = 技能名
//（唯一性不设约束——定位按 trim 逐字相等三态，多命中拒歧义）；description = 触发描述
//（进系统提示词「可用技能」清单，模型据此判断是否加载）；★ icon 列墓碑（2026-11-02 自定义
// 图标功能退役：读写全撤、列与 DEFAULT 值保留免迁移——契约见 SkillDb 头注释）；content = 技能
// 正文（说明书全文，≤ SKILL_CONTENT_MAX 8000 字，经 use_skill 工具结果通道进模型面，
// **永不进 system**）；source = 'user' | 'builtin'（笔 1 恒 'user'，seed 二期消费，预留
// 列避免 v31）；sortOrder = 卡片自定义序（列表序与清单选取序同源，新条目落 max+1 卡底）；
// ★ 有意不加索引——全库 ≤ SKILL_TOTAL_MAX 50 行，全表扫代价可忽略
export const SQL_CREATE_SKILLS: string = 'CREATE TABLE IF NOT EXISTS skills (' +
  'id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT \'\', ' +
  'icon TEXT NOT NULL DEFAULT \'wand_and_stars\', content TEXT NOT NULL DEFAULT \'\', ' +
  'source TEXT NOT NULL DEFAULT \'user\', ' +
  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, ' +
  'sortOrder INTEGER NOT NULL)';
// skill_files v30 新建（2026-09-13 技能层，CRUD 在 SkillDb.ets）：一行一个技能附件文件。
// skillId = 归属技能（随技能删除级联删行——**笔 2 已接线**，与删行同一事务）；纯文本约束
//（md/txt/csv/json 等 UTF-8 文本，**拒二进制、拒脚本
// 语义**）——上限 = 每技能 ≤10 件（SKILL_FILE_MAX_COUNT）、单件 ≤8000 字
//（SKILL_FILE_CONTENT_MAX，< clipToolResult 8192）；白名单窄化与拒脚本语义在笔 2 UI 与
// 断言侧落地，本表只存不解析；★ 有意不加索引（每技能 ≤10 行，随 id 全表扫可忽略）
export const SQL_CREATE_SKILL_FILES: string = 'CREATE TABLE IF NOT EXISTS skill_files (' +
  'id TEXT PRIMARY KEY, skillId TEXT NOT NULL, name TEXT NOT NULL, ' +
  'content TEXT NOT NULL DEFAULT \'\', sortOrder INTEGER NOT NULL, ' +
  'createdAt INTEGER NOT NULL)';
// memories v20 新建（2026-09-08 记忆域，CRUD 在 MemoryDb.ets）：一行一条稳定事实。
// source = 'auto'（退出会话自动整理）/ 'manual'（记忆页手动添加）；assistantId = 沉淀
// 来源助手（'' = 无归属，删助手级联置空）；conversationId = 来源会话（仅追溯，不参与
// 任何级联删除）；sortOrder = 卡片自定义序（v29 加列——列表/注入选取/块内排列/优化序号
// 四路同源；新条目落 max+1 卡底）；updatedAt 仅数据字段与展示用（编辑不再浮顶）
export const SQL_CREATE_MEMORIES: string = 'CREATE TABLE IF NOT EXISTS memories (' +
  'id TEXT PRIMARY KEY, content TEXT NOT NULL, source TEXT NOT NULL DEFAULT \'auto\', ' +
  'assistantId TEXT NOT NULL DEFAULT \'\', conversationId TEXT NOT NULL DEFAULT \'\', ' +
  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, ' +
  'sortOrder INTEGER NOT NULL DEFAULT 0)';
export const SQL_CREATE_MEMORIES_TIME_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_memories_time ON memories(updatedAt)';
// assistant_memories v35 新建（2026-09-20 助手级记忆，CRUD 在 MemoryDb.ets）：一行一条
// 助手级记忆。assistant_id = 归属助手（归属语义——与 memories 表 assistantId 的「沉淀来源
// 标注」语义刻意分离：本列恒等于查询归属，'' 不应出现，DEFAULT 仅迁移兜底；删助手同事务
// 级联删行）；id 前缀 'asmem-'（连字符形态，与全局 'mem-' 同形，仅供人读；manage_memory
// 的跨库拦截靠定位集锁本库，非前缀判据）；
// source/conversationId/sortOrder 语义与 memories 表同构（排序三键 sortOrder→createdAt→
// content 四路同源，新条目落 max+1 卡底）。索引一枚 = 归属查询主路径（按 assistant_id 全量
// 取行）；全表 ≤ MEMORY_MAX_TOTAL 200 行不设 time 索引
export const SQL_CREATE_ASSISTANT_MEMORIES: string =
  'CREATE TABLE IF NOT EXISTS assistant_memories (' +
  'id TEXT PRIMARY KEY, assistantId TEXT NOT NULL DEFAULT \'\', ' +
  'content TEXT NOT NULL DEFAULT \'\', source TEXT NOT NULL DEFAULT \'auto\', ' +
  'conversationId TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL, ' +
  'updatedAt INTEGER NOT NULL, sortOrder INTEGER NOT NULL DEFAULT 0)';
export const SQL_CREATE_ASSISTANT_MEMORIES_ASSISTANT_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_assistant_memories_assistant ' +
  'ON assistant_memories(assistantId)';
// memory_snapshots v41 新建（2026-09-22 记忆优化历史，行读写在 MemoryDb.ets）：一行一份
// 整库快照——记忆整理 / 优化 / 导入落库前自动存档，把「不可撤销」变成「可回退」。
// · libraryId = 'global'（全局库）/ 助手 id（助手库），与 memories / assistant_memories
//   的库判据同源（MEMORY_SCOPE_GLOBAL 常量；禁用 id 前缀判库，见 MemoryDb 头注释）；
// · kind = 'before_opt'（优化前存档）/ 'before_import'（导入前存档）/ ★ 2026-09-27 整理补存档笔
//   新增 'before_sink'（整理前存档）——三类**非兜底槽中的前两类**共用每库 ≤
//   MEMORY_SNAPSHOT_KEEP 份的配额与裁剪（按 kind 各裁一份 = 导入槽永不清理 = 无界增长，故裁剪
//   判据是「排除兜底槽」的否定式，现为 `kind NOT IN (两兜底槽)`）/ 'before_restore'（恢复前兜底）
//   与 'before_sink'（整理前兜底）各每库 ≤1 份、覆盖写、互不干涉——保留规则见 MemoryDb 常量节；
// · note = 给人看的改动摘要（如「改写 3 条 · 合并 2 组」），兜底槽可为空串；
// · itemCount = 快照条目数（列表页不解析 payload 即可显示条数）；
// · payload = 该库全量条目的 JSON 数组串，元素形状 = MemoryRow 全列（含 sortOrder 三时间
//   字段——恢复必须原样写回，理由见 MemoryDb.restoreMemorySnapshot 注释）。
// ★ 列名用 `kind` **不用 `trigger`**——TRIGGER 是 SQLite 保留字，裸用有转义风险。
// ★ 不进 EXPORT_TABLES（本地后悔药不是跨设备资产，D8）；索引一枚 = 该库按类取行的列表主
//   路径（每库 ≤3+1+1 行，索引非性能必需，为「按库+类+时间」三键取行的意图留痕）
export const SQL_CREATE_MEMORY_SNAPSHOTS: string = 'CREATE TABLE IF NOT EXISTS memory_snapshots (' +
  'id TEXT PRIMARY KEY, libraryId TEXT NOT NULL DEFAULT \'global\', ' +
  'kind TEXT NOT NULL DEFAULT \'before_opt\', note TEXT NOT NULL DEFAULT \'\', ' +
  'itemCount INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL, ' +
  'payload TEXT NOT NULL DEFAULT \'[]\')';
export const SQL_CREATE_MEMORY_SNAPSHOTS_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_memory_snapshots_library ' +
  'ON memory_snapshots(libraryId, kind, createdAt)';
// knowledge_books v38 新建（2026-09-21 世界书知识库首版，CRUD 在 KnowledgeDb.ets）：一行
// 一本知识库（用户可见名「知识库」，世界书/World Book/Lorebook 只活在文档与代码注释里）。
// name = 书名（唯一性不设约束——重名不阻断功能，定位按 id）；sortOrder = 卡片自定义序
//（与 memories/skills 同口径：列表序单一来源，新条目落 max+1 卡底）。**有意不加索引**：
// 全库 ≤ KNOWLEDGE_BOOK_MAX 20 行，全表扫代价可忽略（price_templates 同款「有意为之」注释，
// 防后人当疏漏补索引）
export const SQL_CREATE_KNOWLEDGE_BOOKS: string = 'CREATE TABLE IF NOT EXISTS knowledge_books (' +
  'id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL, ' +
  'updatedAt INTEGER NOT NULL, sortOrder INTEGER NOT NULL DEFAULT 0)';
// knowledge_entries v38 新建（CRUD 在 KnowledgeDb.ets）：一行一条知识条目——title 名称 +
// keywords 关键词（可选，**只参与检索加权与展示，不接触发逻辑**——本次姿态为工具化检索，
// 无关键词自动触发；字段先备好，将来若做关键词触发姿态免二次迁移）+ content 正文（纯文本，
// 无 Markdown 渲染）；bookId = 归属知识库（随库删除同事务级联删行）。上限 = 单库
// KNOWLEDGE_ENTRY_MAX 100 条（页面与工具层拦，本层不设约束）。索引一枚 = 按书取行（列表/
// 检索/级联删三路主路径；一条 SQL 取启用书全部条目也是它）。
// source 列 v39 补（2026-09-21 知识库第二笔下本，任务书-知识库写入口与上限放宽-20260921）：
// 条目来源标签，值域 'user'（用户写）/ 'assistant'（助手写）——DEFAULT 'user' = 存量行升级后
// 零变化、用户手写的条目零标记（UI 只标非默认行）。**只在 create 时定、update 不改**（技能库
// skills.source 同为「来源」语义、不随后续编辑翻转）。语义与读写规矩见
// KnowledgeDb.KnowledgeEntryRow 与 KnowledgeText 域件的对应注释
// v51 补四列（2026-10-04 世界书关键词触发笔，任务书-世界书关键词触发-20261004）：关键词
// 自动注入的条目级配置——injectRole/injectPosition/injectDepth 三列与 prompt_templates v7
// 注入三列同形制（值域与语义单源 = RequestInject 的 INJECT_ROLE_*/INJECT_POSITION_*/INJECT_
// DEPTH_MAX 常量表，建表串只存默认值）；enabled = 条目启用开关（1 默认 = 存量行升级后
// 全部启用，行为零变化；0 = 整条停用——自动注入与 search_knowledge 检索双隐藏，
// manage_knowledge 管理清单仍可见）。默认值 = 存量条目零注入配置语义（升级前无自动注入
// 机制，四列落默认即「system/head/0 + 启用」= 无行为变化）。列义与读写规矩见
// KnowledgeDb.KnowledgeEntryRow 对应注释
// v63 补四列（2026-10-26 方案-知识库触发精度-20261025 第一档）：触发精度条目级配置——
// matchCase（0/1 区分大小写，默认 0 = 与旧「两边 toLowerCase」行为一致）/ matchWhole（0/1
// 整词匹配，默认 0 = 子串；仅对纯 ASCII 单词关键词生效，中文键回落子串）/ priority（0~9999，
// 默认 100 = 同值回落原四键，存量顺序零变化；排序第一键降序、全局跨书）/ scanDepth（1~20，
// 默认 8 = 退役常量 KNOWLEDGE_SCAN_MESSAGES 同值）。四列尾部追加（与 v63 迁移 ALTER 加列的
// 列序一致，新装库与升级库列序相同）；值域与归一单源 = KnowledgeText 的
// KNOWLEDGE_PRIORITY_*/KNOWLEDGE_SCAN_* 常量族与 clampKnowledgePriority/clampKnowledgeScan
export const SQL_CREATE_KNOWLEDGE_ENTRIES: string = 'CREATE TABLE IF NOT EXISTS knowledge_entries (' +
  'id TEXT PRIMARY KEY, bookId TEXT NOT NULL DEFAULT \'\', title TEXT NOT NULL DEFAULT \'\', ' +
  'keywords TEXT NOT NULL DEFAULT \'\', content TEXT NOT NULL DEFAULT \'\', ' +
  'source TEXT NOT NULL DEFAULT \'user\', ' +
  'injectRole TEXT NOT NULL DEFAULT \'system\', ' +
  'injectPosition TEXT NOT NULL DEFAULT \'head\', ' +
  'injectDepth INTEGER NOT NULL DEFAULT 0, ' +
  'enabled INTEGER NOT NULL DEFAULT 1, ' +
  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, ' +
  'sortOrder INTEGER NOT NULL DEFAULT 0, ' +
  'matchCase INTEGER NOT NULL DEFAULT 0, ' +
  'matchWhole INTEGER NOT NULL DEFAULT 0, ' +
  'priority INTEGER NOT NULL DEFAULT 100, ' +
  'scanDepth INTEGER NOT NULL DEFAULT 8)';
export const SQL_CREATE_KNOWLEDGE_ENTRIES_BOOK_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_knowledge_entries_book ON knowledge_entries(bookId)';
// knowledge_files v43 新建（2026-09-23 知识库文件笔，CRUD 在 KnowledgeDb.ets）：一行一个
// 知识条目的纯文本附件。entryId = 归属条目（**挂条目不挂库**——与技能附件挂技能行同构；
// 随条目删除与删库两路级联删行，都在各自事务内）；name = 件名（**本条目内唯一**——件名是
// 模型取件的唯一定位键，同名两件会让「取到哪一份」不可预期，写入侧硬拒）；content = 纯文本。
// 上限 = 每条目 ≤ KNOWLEDGE_FILE_MAX_COUNT 10 件、单件 ≤ KNOWLEDGE_FILE_CONTENT_MAX 8000 字
//（< clipToolResult 8192，保证单件恒完整送达）；扩展名白名单与拒二进制/脚本语义在
// KnowledgeText 校验面。★ **本表只存文本**：二进制文档（PDF/Word 等）若将来要做，另表另链
//（须先把 DocumentParse 的抽取文本落库）——禁塞进本表，混入 blob 会让「统一按文本建索引」
// 的向量化升级做不成。★ 不进检索索引、不进注入块（文件是条目附属的参考资料，只经
// manage_knowledge 的 read_file 按件名取用）。★ 有意不加索引：主路径 = 按 entryId 取行
//（每条目 ≤10 行，随 id 全表扫代价可忽略；skill_files 同款「有意为之」注释，防后人当疏漏补）
export const SQL_CREATE_KNOWLEDGE_FILES: string = 'CREATE TABLE IF NOT EXISTS knowledge_files (' +
  'id TEXT PRIMARY KEY, entryId TEXT NOT NULL DEFAULT \'\', name TEXT NOT NULL DEFAULT \'\', ' +
  'content TEXT NOT NULL DEFAULT \'\', sortOrder INTEGER NOT NULL DEFAULT 0, ' +
  'createdAt INTEGER NOT NULL)';
// message_attachments v23 新建（2026-09-09 附件全量落盘第一轮，CRUD 在 AttachmentDb.ets）：
// 一行一个已发送附件。id = 附件 fileId（与文件名 <id>.<ext> 同源）；conversationId 冗余列
//（级联删与按会话统计免 join；值不可变——消息不换会话）；kind = 'image' | 'text' | 'doc'
//（classifyByName 全集）；parsedText 仅 kind='doc' 落值（≤120K 字符，DocumentParse.
// MAX_EXTRACTED_CHARS 侧截断）；localPath 相对 filesDir（attachments/<id>.<ext>）——换
// 设备/将来导出迁移拼当前沙箱前缀即可用，禁绝对路径入库；索引两枚 = 消息级联删 + 按会话查
export const SQL_CREATE_MESSAGE_ATTACHMENTS: string =
  'CREATE TABLE IF NOT EXISTS message_attachments (' +
  'id TEXT PRIMARY KEY, messageId TEXT NOT NULL, conversationId TEXT NOT NULL DEFAULT \'\', ' +
  'kind TEXT NOT NULL DEFAULT \'text\', name TEXT NOT NULL DEFAULT \'\', ' +
  'mime TEXT NOT NULL DEFAULT \'\', size INTEGER NOT NULL DEFAULT 0, ' +
  'localPath TEXT NOT NULL DEFAULT \'\', parsedText TEXT NOT NULL DEFAULT \'\', ' +
  'createdAt INTEGER NOT NULL)';
export const SQL_CREATE_MESSAGE_ATTACHMENTS_MSG_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_message_attachments_msg ON message_attachments(messageId)';
export const SQL_CREATE_MESSAGE_ATTACHMENTS_CONV_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_message_attachments_conv ON message_attachments(conversationId)';
// token_usage_events v18 新建（2026-09-06 用量账本，CRUD/聚合在 UsageStatsDb.ets）：
// 只追加不更新；providerId/modelId 记「产生消耗时」的归属快照（DEFAULT '' = 兜底——
// 取钥间隙收尾等边缘态不留 NULL）；索引两枚 = 会话级联删（conv）与逐日/总览聚合（time）。
// v26（2026-09-10 缓存命中）补 cachedTokens（整轮命中缓存读 token，语义见 ChatDbMigrate v26 注释）；
// v27（2026-09-10 费用估计）补 purpose（用途码，四值语义见 ChatDbMigrate v27 注释——DEFAULT 'chat'
// = 存量行回填语义：表自 v18 起唯一写入点就是聊天发送链，全量历史行按聊天口径继续被
// 用量统计页三聚合消费，零迁移零回归）；
// v44（2026-09-23 首字耗时）补 firstTokenMs（整轮首字耗时毫秒，0 = 无该指标——口径见
// ChatDbMigrate v44 注释）
// v46 账本幂等身份四列（2026-09-26 消息架构整合笔2——请求级账本去重，J10 冻结去重规则
// 供笔3）：runId/attemptId/branchId = 笔1 词表同源弱链；requestId = 幂等事件身份——非空时
// 插入前查重、命中即跳过（同一请求重复回调不重复入账），存量行恒空串 = 无请求身份不参与
// 去重。★ 禁建 UNIQUE 索引：存量多行空串会在普通 UNIQUE 下互斥——部分索引未获官方背书前
// 不引入；去重单点在仓储命令 MessageBranchDb.recordUsageEvent。★ 注释置声明前防字面量
// 提取器误吸引号词（conversations 同款实锤）。
export const SQL_CREATE_TOKEN_USAGE_EVENTS: string = 'CREATE TABLE IF NOT EXISTS token_usage_events (' +
  'id TEXT PRIMARY KEY, conversationId TEXT NOT NULL DEFAULT \'\', ' +
  'messageId TEXT NOT NULL DEFAULT \'\', providerId TEXT NOT NULL DEFAULT \'\', ' +
  'modelId TEXT NOT NULL DEFAULT \'\', promptTokens INTEGER NOT NULL DEFAULT 0, ' +
  'completionTokens INTEGER NOT NULL DEFAULT 0, totalTokens INTEGER NOT NULL DEFAULT 0, ' +
  'durationMs INTEGER NOT NULL DEFAULT 0, firstTokenMs INTEGER NOT NULL DEFAULT 0, ' +
  'cachedTokens INTEGER NOT NULL DEFAULT 0, ' +
  'purpose TEXT NOT NULL DEFAULT \'chat\', createdAt INTEGER NOT NULL, ' +
  'runId TEXT NOT NULL DEFAULT \'\', attemptId TEXT NOT NULL DEFAULT \'\', ' +
  'branchId TEXT NOT NULL DEFAULT \'\', requestId TEXT NOT NULL DEFAULT \'\', ' +
  'serverToolsUsage TEXT NOT NULL DEFAULT \'\')';
  // v65（2026-11-14 DS 全家桶二期 S2/#7）：serverToolsUsage = 本轮官方服务端工具计次
  // JSON 串（{"search":n,"fetch":n,"image":n}）；'' = 无计次（小任务链与非 DS 轮天然
  // 空串）。落库后重进会话仍能在用量气泡列出「搜索 N 次 / 抓取 N 页 / 图搜 N 张」——
  // 不落库则只在当轮可见。列有意无约束（无语义 = ''，与 cachedTokens 同理由）
// price_templates v28 新建（2026-09-11 价格模板，CRUD 在 PriceTemplateDb.ets）：一行一套
// 价格模板。providerId = 归属服务商（模板按服务商隔离，随服务商删除级联清理）；name =
// 模板名（同服务商内禁同名由调用侧查重，本层不拦）；priceConfig = 价格 JSON 串原文
//（serializePriceConfig 产出，'' 语义不出现——保存链拦截半份配置后才可入库）。★ 有意
// 不加索引：每服务商 ≤ PRICE_TEMPLATE_MAX（20）行，按 providerId 全表扫代价可忽略
export const SQL_CREATE_PRICE_TEMPLATES: string = 'CREATE TABLE IF NOT EXISTS price_templates (' +
  'id TEXT PRIMARY KEY, providerId TEXT NOT NULL, name TEXT NOT NULL, ' +
  'priceConfig TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL)';
export const SQL_CREATE_TOKEN_USAGE_CONV_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_token_usage_conv ON token_usage_events(conversationId)';
export const SQL_CREATE_TOKEN_USAGE_TIME_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_token_usage_time ON token_usage_events(createdAt)';
export const SQL_CREATE_MESSAGES_INDEX: string = 'CREATE INDEX IF NOT EXISTS idx_messages_conv ' +
  'ON messages(conversationId, createdAt)';
// idx_messages_conv_seq（v37，2026-09-21 消息存储机制改造笔 1）：按会话取 seq 序——笔 3 的
// 读取切换与回填的「会话内缺号/重号」判定同走它。建表侧与 v36→v37 迁移分支两处同款
export const SQL_CREATE_MESSAGES_SEQ_INDEX: string = 'CREATE INDEX IF NOT EXISTS idx_messages_conv_seq ' +
  'ON messages(conversationId, seq)';
export const SQL_CREATE_PROVIDER_MODELS_INDEX: string = 'CREATE INDEX IF NOT EXISTS idx_provider_models ' +
  'ON provider_models(providerId)';
export const SQL_CREATE_PROVIDER_KEYS_INDEX: string = 'CREATE INDEX IF NOT EXISTS idx_provider_keys ' +
  'ON provider_keys(providerId)';
// ═══ 图侧域（v46，2026-09-26 消息架构整合笔2）═══
// 六表语义总纲 = ChatDbMigrate v46 版本注释 + 消息架构整合总纲§5 两道闸；命令层单源 =
// MessageBranchDb.ets（出生/读写编排 = ChatContextSource，★ 2026-09-26 旧会话墓碑笔起
// 迁移器与三态状态机已整件退役）。本文件只建表。
// ★ J0 红线：表自空起步——本笔零构图零图写，生产会话不进这些表（验证全在隔离库）。
// branches：一行一个分支。headMessageId = 分支头节点（messages.id 弱链，**可空**——无行
// 会话 head 语义在存储层成立〔总纲§4 I3〕）；parentBranchId = fork 来源（根分支 NULL）。
// 索引一枚 = 按会话取分支（分支树主路径）
export const SQL_CREATE_BRANCHES: string = 'CREATE TABLE IF NOT EXISTS branches (' +
  'id TEXT PRIMARY KEY, conversationId TEXT NOT NULL, ' +
  'parentBranchId TEXT DEFAULT NULL, headMessageId TEXT DEFAULT NULL, ' +
  'name TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL)';
export const SQL_CREATE_BRANCHES_CONV_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_branches_conv ON branches(conversationId)';
// generation_runs：一行一次运行（runId = 笔1 词表 run_<毫秒>_<序号>，**升持久主键即同一
// 身份不重编号**〔I8/MessageContracts 冻结词表〕）。inputAnchorMessageId = 输入锚点（触发
// 本 run 的 user 节点）；revision = 乐观并发版本（占用拒绝冲突〔I2〕，CAS 递增）；
// status = prepared/running/finished/failed（值域常量在 MessageBranchDb）；
// checkpoint = 完整交换检查点 JSON（失败/取消只推进完整交换检查点〔J6〕，'' = 无）；
// diagnosticMessageId = 终态诊断节点引用（诊断节点也是可达根〔总纲§3〕）。
// 索引一枚 = 按会话取 run
export const SQL_CREATE_GENERATION_RUNS: string =
  'CREATE TABLE IF NOT EXISTS generation_runs (' +
  'id TEXT PRIMARY KEY, conversationId TEXT NOT NULL, branchId TEXT NOT NULL DEFAULT \'\', ' +
  'attemptEpoch INTEGER NOT NULL DEFAULT 1, inputAnchorMessageId TEXT NOT NULL DEFAULT \'\', ' +
  'revision INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT \'prepared\', ' +
  'checkpoint TEXT NOT NULL DEFAULT \'\', diagnosticMessageId TEXT NOT NULL DEFAULT \'\', ' +
  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL)';
export const SQL_CREATE_GENERATION_RUNS_CONV_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_generation_runs_conv ON generation_runs(conversationId)';
// tool_facts：一行一个工具事实（J10 四态机：prepared → dispatch_intent → result_confirmed /
// 失败终态 failed——派发前先提交意图，恢复无确认结果的 dispatch_intent =「执行结果未知」
// 不自动重放）。payload/result = 调用参与结果 JSON 串原文（结构单源在工具域，本表透传）。
// v54（2026-10-07 会话轨迹视图 S0，任务书-会话轨迹视图-20261007 §3）：补 finishedAt
//（终态时刻毫秒，0 = 无终态时刻——未终态行与旧行；唯一写口 = MessageBranchDb.recordToolFact，
// 新建落 0、终态推进打戳、dispatch_intent 不动；语义与消费口径见 ChatDbMigrate v54 版本注释）。
// 索引一枚 = 按 run 取事实链
export const SQL_CREATE_TOOL_FACTS: string = 'CREATE TABLE IF NOT EXISTS tool_facts (' +
  'id TEXT PRIMARY KEY, runId TEXT NOT NULL, attemptId TEXT NOT NULL DEFAULT \'\', ' +
  'name TEXT NOT NULL DEFAULT \'\', state TEXT NOT NULL DEFAULT \'prepared\', ' +
  'payload TEXT NOT NULL DEFAULT \'\', result TEXT NOT NULL DEFAULT \'\', ' +
  'createdAt INTEGER NOT NULL, ' +
  'finishedAt INTEGER NOT NULL DEFAULT 0)';
export const SQL_CREATE_TOOL_FACTS_RUN_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_tool_facts_run ON tool_facts(runId)';
// summary_bindings：一行一条摘要绑定（摘要正文仍在 messages role='summary' 行〔J8 分案
// §3「正文不另建第二份正文仓」〕，本表承载**稳定节点范围**——coversFromSeq/coversToSeq =
// 覆盖的 seq 区间；coversToSeq **可空** = 「覆盖边界不可证」（W7 污染库迁移时禁自动裁剪的
// 语义标记，读侧见 NULL 即不裁）。dependsOnBindingId = 前摘要依赖链（'' = 无）。
// 索引一枚 = 按会话取绑定
export const SQL_CREATE_SUMMARY_BINDINGS: string =
  'CREATE TABLE IF NOT EXISTS summary_bindings (' +
  'id TEXT PRIMARY KEY, conversationId TEXT NOT NULL, summaryMessageId TEXT NOT NULL, ' +
  'coversFromSeq INTEGER DEFAULT NULL, coversToSeq INTEGER DEFAULT NULL, ' +
  'dependsOnBindingId TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL)';
export const SQL_CREATE_SUMMARY_BINDINGS_CONV_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_summary_bindings_conv ON summary_bindings(conversationId)';
// attachment_refs：一行一个图侧附件引用（未来归属真源〔J7〕；资源行仍在 message_attachments
// 不动）。nodeId = 挂载节点（graph 资源挂 graph 节点；legacy 迁移资源挂原 messageId 对应
// 节点）。★ messageId 空串占位规则（J7 冻结）：graph 新增资源写 message_attachments.messageId
// = '' 作兼容占位（该列现 NOT NULL 不改约束），空串不表达归属——归属判定恒经本表 refs；
// 空串资源无 refs = 保护不删。索引两枚 = 按会话取 refs / 按资源行反查
export const SQL_CREATE_ATTACHMENT_REFS: string = 'CREATE TABLE IF NOT EXISTS attachment_refs (' +
  'id TEXT PRIMARY KEY, conversationId TEXT NOT NULL, attachmentId TEXT NOT NULL, ' +
  'nodeId TEXT NOT NULL, createdAt INTEGER NOT NULL)';
export const SQL_CREATE_ATTACHMENT_REFS_CONV_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_attachment_refs_conv ON attachment_refs(conversationId)';
export const SQL_CREATE_ATTACHMENT_REFS_ATTACH_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_attachment_refs_attach ON attachment_refs(attachmentId)';
// graph_capability：单行图能力标记（双层降级守卫〔J2〕第二层的持久真源——**独立于
// store.version**：笔3 可在不升 DB_VERSION 的情况下把 level 1→2，仅版本守卫的旧构建会
// 漏判）。id 恒 'graph'；level 值域 = 0 无图 / 1 schema 已备图未开启（本笔写）/ 2 图已
// 开启（笔3 写）。守卫读侧 = ChatDbMigrate.readGraphCapabilityLevel，本包支持上限常量
// GRAPH_CAPABILITY_SUPPORTED 同文件。索引无（单行点查）
export const SQL_CREATE_GRAPH_CAPABILITY: string = 'CREATE TABLE IF NOT EXISTS graph_capability (' +
  'id TEXT PRIMARY KEY, level INTEGER NOT NULL DEFAULT 0)';

// http_templates（2026-10-01 方案-HTTP工具完善 批 3 笔 6「请求复用面」v47 新表；表语义与
// CRUD 单源 = HttpTemplateDb.ets，本件只承载建表 SQL——全仓建表 SQL 常量单一来源。列义：
// name 显示名〔同库唯一，定案②同名就地拒绝〕/ slug 注册工具名〔tpl_<id>，定案③恒定〕/
// url_template・body_template・headers_json 含 {参数} 占位〔渲染纯函数在
// HttpTemplate.assembleTemplateRequest〕/ params_json 参数定义〔模型面 schema 唯一来源〕。
// 索引无——条数上限 20 的小表，全表扫即查）。迁移分支（v47）与新装 ensureSchema 共用本串，
// CREATE IF NOT EXISTS 幂等（铁律②）
export const SQL_CREATE_HTTP_TEMPLATES: string = 'CREATE TABLE IF NOT EXISTS http_templates (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  "name TEXT NOT NULL DEFAULT '', " +
  "slug TEXT NOT NULL DEFAULT '', " +
  "method TEXT NOT NULL DEFAULT 'GET', " +
  "url_template TEXT NOT NULL DEFAULT '', " +
  "headers_json TEXT NOT NULL DEFAULT '[]', " +
  "body_template TEXT NOT NULL DEFAULT '', " +
  "params_json TEXT NOT NULL DEFAULT '[]', " +
  'created_at INTEGER NOT NULL DEFAULT 0, ' +
  'updated_at INTEGER NOT NULL DEFAULT 0)';

// workspace_files（2026-10-01 方案-文件工作区-20261001 v48 新表；行读写与文件 IO 单源 =
// WorkspaceDb.ets，纯函数在 WorkspaceUtil.ets，用户可见名「文件工作区」）：一行一个工作区
// 文件。列义：id = fileId（与物理文件名 <id>.<ext> 同源，UUID 铸造）；name = 显示名（模型
// 给的 name / 用户原文件名，非法字符已替换，同名 write 覆盖 / 上传自动避重——目录内理论
// 唯一，跨目录允许同名）；dir = 相对工作区根的 / 分隔路径串，'' = 根（v49 加列，文件夹与
// 模型目录工具笔；同时是物理目录结构——文件物理路径 workspace/<dir段…>/<id>.<ext>）；
// kind = 'image' | 'text' | 'doc'（classifyByName 全集）| 'other'（2026-10-01 笔 7 类型闸
// 放宽的兜底档）| 'dir'（★ 2026-10-02 目录行笔：行类型判别位非文件分类，文件夹一等行）；
// mime 按扩展名派生（无命中
// 空串）；localPath 相对 filesDir（workspace/<id>.<ext>，dir 非空时带目录段）——换设备/
// 将来导出迁移拼当前沙箱前缀即可用，禁绝对路径入库；source = 'user' | 'assistant' |
// 'download' | 'recovered'（产生者标注；recovered = 启动对账补录的磁盘恢复件，v49 增）；
// conversationId /
// ownerAssistantId = 追溯列（模型写入路填充哪次会话哪个助手写的；上传路恒 ''；★ 删会话/
// 删助手**零级联不置空**——工作区是跨会话持久资产，照 memories 表「conversationId 仅追溯」
// 先例）；updatedAt = 覆盖写更新。★ 有意不加索引（含 (dir,name) 唯一索引——防线 = 应用层
// 约定 + 多命中报错，照 price_templates「有意不加索引」同判据，防 INSERT OR REPLACE 语义
// 意外变化）：件数上限（WorkspaceUtil 常量现值 1000），全表
// 扫代价可忽略（防后人当疏漏补）。★ 不进
// EXPORT_TABLES——工作区文件不随备份导出（全工程文件类资产先例一致，方案 §8-6）。
// sortOrder = 目录行自定义序（v50 加列，2026-10-04 文件夹段排序笔；**只目录行消费**——
// 文件行恒 0 不参与任何排序；存量目录行全 0 = 名称字典序兜底 = 升级前列表序逐字节不变，
// 无数据回填；语义与写点单源 = WorkspaceDb.ets「目录排序域」节）。
// ocr 六列（v53 加列，2026-10-04 方案-工作区识别文字-20261004；读写与指纹/状态纯函数单源 =
// WorkspaceDbOcr.ets）：ocrText = 识别文本（'' = 未识别）；ocrEngine = 产出引擎名
//（'system'|'builtin'|'model' | 文档解析引擎名）；ocrAt = 识别完成时刻；ocrFileMtime /
// ocrFileSize = **识别起始时刻**的文件 stat 快照（ms/字节——有效性指纹，判据
// ocrStateOf：两值与现读 stat 双等才 fresh，**禁用行 updatedAt 做指纹**——改名/移动会刷
// updatedAt 而内容未变）；ocrEditedAt = 用户校对保存时刻（0 = 未校对）。★ 覆盖即清红线：
// **这六列禁写进任何 insert/upsert 列清单**——同名覆盖走 upsertWorkspaceRow 的 INSERT OR
// REPLACE 未列列重置默认，六列不在清单 = 覆盖天然清掉识别文本（状态回 none，方案 §3.1）。
// 迁移分支（v48 建表 / v49 加 dir 列 / v50 加 sortOrder 列 / v53 加 ocr 六列）与新装
// ensureSchema 共用本串，CREATE IF NOT EXISTS 幂等（铁律②）。
// 注释置声明前（防字面量提取器误吸，token_usage_events 同款实锤口径）
export const SQL_CREATE_WORKSPACE_FILES: string = 'CREATE TABLE IF NOT EXISTS workspace_files (' +
  'id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT \'\', ' +
  'dir TEXT NOT NULL DEFAULT \'\', ' +
  'kind TEXT NOT NULL DEFAULT \'text\', mime TEXT NOT NULL DEFAULT \'\', ' +
  'size INTEGER NOT NULL DEFAULT 0, localPath TEXT NOT NULL DEFAULT \'\', ' +
  'source TEXT NOT NULL DEFAULT \'assistant\', conversationId TEXT NOT NULL DEFAULT \'\', ' +
  'ownerAssistantId TEXT NOT NULL DEFAULT \'\', createdAt INTEGER NOT NULL, ' +
  'updatedAt INTEGER NOT NULL, sortOrder INTEGER NOT NULL DEFAULT 0, ' +
  "ocrText TEXT NOT NULL DEFAULT '', " +
  "ocrEngine TEXT NOT NULL DEFAULT '', " +
  'ocrAt INTEGER NOT NULL DEFAULT 0, ' +
  'ocrFileMtime INTEGER NOT NULL DEFAULT 0, ' +
  'ocrFileSize INTEGER NOT NULL DEFAULT 0, ' +
  'ocrEditedAt INTEGER NOT NULL DEFAULT 0)';

// folder_mounts（2026-10-08 方案-文件夹挂载-20261008 笔 1「地基 + 管理面」v55 新表、
// M2 写面笔 v56 拆 aiAccess 列；行读写单源 = MountDb.ets、纯函数在 MountUtil.ets，用户可见名
// 「文件夹挂载」）：一行一个挂载。列义：name = 挂载名（用户起的纯标签、与文件夹真名无关）；
// dirUri = 系统目录 URI（file://docs/…——FOLDER 选择器产出、persistPermission 持久授权的
// 对象）；mode = 应用层模式镜像（0 只读 / 1 读写；系统真值在授权模式位，映射单源 =
// MountUtil.mountModeMask——切换模式 = 重新拉选择器再 persist 新模式位，本列随写）；
// createdAt = 落行时刻毫秒；lastCheckAt = 最近一次授权校验时刻（进页
// checkPersistentPermission 后回写，0 = 未校验）；lastError = 最近一次校验失败或授权失败
// 文本（'' = 正常）。★ aiAccess 列 v56 拆除（M2 笔 2026-10-08 决明拍板「允许 AI 使用」
// 开关整面退役——想断访问直接移除挂载，移除功能能代替；单层门 = 助手工具页组卡开关）。
// 索引无——件数上限 MOUNT_MAX_COUNT（应用层先于系统触发可管理行为），全表扫即查（照
// price_templates「有意不加索引」判据）。★ 不进 EXPORT_TABLES——授权记录存系统侧、按设备
// 隔离，备份不含本表（方案 §3.6 备份排除；对齐 Cube「不随备份和传送包迁移」）。迁移分支
//（v55 建表 / v56 拆列）与新装 ensureSchema 共用本串，CREATE IF NOT EXISTS 幂等（铁律②）
export const SQL_CREATE_FOLDER_MOUNTS: string = 'CREATE TABLE IF NOT EXISTS folder_mounts (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  "name TEXT NOT NULL DEFAULT '', " +
  "dirUri TEXT NOT NULL DEFAULT '', " +
  'mode INTEGER NOT NULL DEFAULT 0, ' +
  'createdAt INTEGER NOT NULL DEFAULT 0, ' +
  'lastCheckAt INTEGER NOT NULL DEFAULT 0, ' +
  "lastError TEXT NOT NULL DEFAULT '')";

// send_queue_items（2026-10-17 排队插队施工总案 Q3，v57 新表；行读写单源 =
// ChatSendQueueDb.ets）：一行一条排队中的用户消息。列义：id = 条目 id（排队域铸造，
// `queue_<ms>_<seq>`，与内存条目同一身份）；conversationId = 归属会话（G6 会话锚点，
// 级联删挂 ChatDb.deleteConversations 与 AssistantDb.deleteAssistantCascade 两事务，
// 防孤儿排队行）；sortOrder = 会话内队列序（0 起；顺序真源 = 本列 + createdAt + id 决胜，
// 换序 = 整组重写 ≤20 行）；payload = 消息载荷 JSON 串（{text, designateId, queuedAt}，
// **文本 only 无附件序列化面**——带附件由 Q2 入口层拒绝入队，裁定丙-8）；createdAt =
// 入队时刻（= payload.queuedAt，冗余列供排序决胜）；updatedAt = 编辑/换序回写时刻。
// ★ 行存在即 QUEUED（唯一持久化形态）：出队删行搭车 prepareRun 单事务（与 user 消息行 +
// run 行同事务提交——库中永无 inFlight 歧义行，hydrate 零清标志、天然幂等）；崩溃两分支 =
// 提交前（行在 + user 事实未落 → 重启重投，不丢不重）/ 提交后（行删 + user 事实在 →
// sweepStaleGraphRuns 既有链收口）。**本表不进 EXPORT_TABLES**——排队是发送意图非资产
// 事实（price_templates/folder_mounts/memory_snapshots 先例，恢复语义无需定义）。
// 索引无——单会话 ≤ QUEUE_MAX_ITEMS 20 行、级联清空，全表扫代价可忽略（照 price_templates
// 「有意不加索引」判据）。迁移分支（v57 建表）与新装 ensureSchema 共用本串，CREATE IF
// NOT EXISTS 幂等（铁律②）
export const SQL_CREATE_SEND_QUEUE_ITEMS: string = 'CREATE TABLE IF NOT EXISTS send_queue_items (' +
  'id TEXT PRIMARY KEY, ' +
  'conversationId TEXT NOT NULL, ' +
  'sortOrder INTEGER NOT NULL DEFAULT 0, ' +
  'payload TEXT NOT NULL, ' +
  'createdAt INTEGER NOT NULL DEFAULT 0, ' +
  'updatedAt INTEGER NOT NULL DEFAULT 0)';

// send_queue_state（2026-10-17 排队暂停位落库笔，v58 新表；行读写单源 =
// ChatSendQueueDb.ets）：一行一会话的排队运行态持久真源。为什么独立成表而不加列——暂停是
// **会话级**状态（不是条目级），且空队列也允许存在（暂停位在队列清空前可能先于末项消失）；
// 挂 send_queue_items 行上会随出队删行一起丢。列义：conversationId = 会话 id（主键，一会话
// 至多一行）；runState = 'ACTIVE' | 'PAUSED'（值域同 ChatSendQueueCtrl.QueueRunState）；
// pauseReason = '' | 'user' | 'error' | 'stopped' | 'delivery'（值域单源
// ChatSendQueueCtrl.QueuePauseReason）；updatedAt = 最近一次状态变更时刻。
// ★ 行语义：无行 = 从未写过 = ACTIVE（历史库/新会话的缺省）；runState 只认 'PAUSED'，其余脏值
// 由队列域归一为 ACTIVE（防脏行把队列永久锁死）。ACTIVE 行允许残留（等于缺省值，下次暂停
// 直接 UPSERT 覆盖）；**队列为空时队列域强制回 ACTIVE 并回写**，不留「PAUSED + 0 行」组合。
// 级联删挂 ChatDb.deleteConversations 与 AssistantDb.deleteAssistantCascade 两事务（与
// send_queue_items 同笔同事务，防孤儿行）。**本表不进 EXPORT_TABLES**——与排队行同口径
// （发送意图非资产事实）。索引无——主键即查、一会话一行。迁移分支（v58 建表）与新装
// ensureSchema 共用本串，CREATE IF NOT EXISTS 幂等（铁律②）
export const SQL_CREATE_SEND_QUEUE_STATE: string = 'CREATE TABLE IF NOT EXISTS send_queue_state (' +
  'conversationId TEXT PRIMARY KEY, ' +
  "runState TEXT NOT NULL DEFAULT 'ACTIVE', " +
  "pauseReason TEXT NOT NULL DEFAULT '', " +
  'updatedAt INTEGER NOT NULL DEFAULT 0)';

// mcp_servers（2026-10-19 方案-MCP页施工方案 B2，v59 新表；行读写单源 = McpDb.ets、纯函数
// 在 common/McpText.ets，用户可见名「MCP」）：一行一台 MCP 服务器（Streamable HTTP 端点的
// 全局配置资产，按助手绑定消费——assistants.mcpServers 弱链 id 集，导入不校验引用完整
// 性）。主键 id = TEXT UUID（util.generateRandomUUID(true)，insertMcpServer 铸造——跨备份/
// 恢复稳定，skills / knowledge / providers 等 id TEXT 主键惯例同款；不采 INTEGER 自增 = 自
// 增依赖导出保序、引用完整性弱）。列义：
// · name = 显示名，同时是三段工具名（mcp__name__tool）的前缀段——约束 ^[A-Za-z0-9]+$
//   （编辑页实时校验 + McpDb 增改闸 + 同步期兜底三道）；查重闸在 McpDb（同 name 拒绝）；
// · url = Streamable HTTP 端点，https?:// 校验在编辑页保存闸（数据层不做二次判定——两处
//   判定 = 两处漂移面）；
// · enabled = 服务器总开关（0 = 注销注册表条目 + 不注入任何对话，编辑页表单首行开关）；
// · headersJson = 请求头**元数据** [{"name":"Authorization","hasValue":true}]——★ 密钥
//   红线：头值明文恒不落本列，值只进 Asset（KeyStore 第九形态，别名 aic.mcp.<serverId>.
//   <头序号>；DB 行只存名称与标记，备份/列表/日志可见面零明文——AppPreferencesHttp 分流
//   先例同口径）；
// · toolsJson = 工具缓存 [{"name","description","inputSchema"}]（inputSchema 恒为 $ref
//   已展开态——B6 落地展开函数）；tools/list 成功后整表替换回写（updateMcpServerTools
//   单口）；缓存恢复注册表消费（启动 syncMcpTools 不发网络，B6）；
// · lastSyncAt = 最近一次同步成功时刻毫秒（0 = 从未同步）；
// · lastError = 最近一次同步/测连失败摘要（中文，可含官方错误 message，不含头值；'' = 正常）；
// · createdAt = 落行时刻毫秒，列表排序键（createdAt ASC, id ASC 稳定序）；
// · authKind = 认证方式四选（v60，方案-MCP二期对标增强 A）：'none' 无需认证 / 'bearer'
//   Bearer Token / 'apiKey' API Key / 'custom' 自定义请求头。**底层链路零分叉**——后三档
//   保存时均由编辑页组装为请求头组（headersJson + Asset），本列只是「如何组装」的意图标记；
//   存量行默认 'custom' = 忠实回填现行自定义头组 UI（零行为变化）；
// · protocolVersion = 广告协议版本（v60，方案-MCP二期对标增强 B1）：'' = 自动协商（广告
//   2025-06-18，现行为）；否则为强制广告版本串（'2025-03-26' / '2025-06-18' / '2025-11-25'
//   / '2026-07-28'，合法域单源 = McpRpc.MCP_VERSIONS_LEGAL）。只升级握手广告值与版本头；
//   新形态报文服务器仍可能连不上（UI 说明小字如实交代）。
// ★ 有界：服务器上限 MCP_SERVERS_MAX = 8（insertMcpServer 上限闸）× 单服务器工具缓存
//   MCP_TOOLS_CACHE_MAX = 32 件（超限 = 同步失败报中文错，P0-1 不静默截断）× 请求头
//   ≤ MCP_HEADERS_MAX 5 行（表单闸）；索引无——件数 ≤8 全表扫即查（folder_mounts「有意
//   不加索引」同判据，防后人当疏漏补）。★ 进 EXPORT_TABLES（用户搭建资产随备份走；
//   头值明文不随——Asset 分流）。迁移分支（v59 建表 + assistants 加列双动作；v60 加两列）
//   与新装 ensureSchema 共用本串，CREATE IF NOT EXISTS 幂等（铁律②）。注释置声明前（防
//   字面量提取器误吸引号词，token_usage_events 同款实锤口径）
export const SQL_CREATE_MCP_SERVERS: string = 'CREATE TABLE IF NOT EXISTS mcp_servers (' +
  'id TEXT PRIMARY KEY, ' +
  "name TEXT NOT NULL DEFAULT '', " +
  "url TEXT NOT NULL DEFAULT '', " +
  'enabled INTEGER NOT NULL DEFAULT 1, ' +
  "headersJson TEXT NOT NULL DEFAULT '[]', " +
  "toolsJson TEXT NOT NULL DEFAULT '[]', " +
  'lastSyncAt INTEGER NOT NULL DEFAULT 0, ' +
  "lastError TEXT NOT NULL DEFAULT '', " +
  'createdAt INTEGER NOT NULL DEFAULT 0, ' +
  "authKind TEXT NOT NULL DEFAULT 'custom', " +
  "protocolVersion TEXT NOT NULL DEFAULT '')";
