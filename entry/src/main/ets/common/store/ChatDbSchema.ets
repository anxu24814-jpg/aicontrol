// 建表 SQL 常量域（2026-09-23 上下文压缩笔自 ChatDbMigrate.ets 域级最小拆分——该件剔头
// 1189 行已越 1200 硬线且技术债务清单早已按候选缝「SQL 建表常量整块外迁」建档，本笔是
// 压缩摘要在该域的实质增量，按宪法「单文件规模上限」条先按建档缝拆再落改动）：
// 全部表与索引的 CREATE 语句常量单一来源在本文件，**新装执行与迁移分支仍在 ChatDbMigrate**
// （ensureSchema / migrateSchema 依次引用本件常量）——本文件零函数零 import，纯常量资产；
// 各列语义与版本沿革的权威注释 = ChatDbMigrate.ets 头部版本史，块内注释只留列义速查并
// 回指该处。断言面注意：assert-store-consistency 71/143/171 组读建表 SQL 文本的判据已
// 随本笔回指本文件。
// ★ messages 表 v42 起含 coversToSeq 列（压缩摘要行覆盖边界，详见 ChatDbMigrate v42
//   版本注释）；列位置 = variant_active 与 seq 之间（seq 恒为建表末列——143 ⑨ 钉住收尾形态）。
export const SQL_CREATE_PROMPT_TEMPLATES: string = 'CREATE TABLE IF NOT EXISTS prompt_templates (' +
  'id TEXT PRIMARY KEY, name TEXT NOT NULL, content TEXT NOT NULL DEFAULT \'\', ' +
  'isGlobal INTEGER NOT NULL DEFAULT 0, createdAt INTEGER NOT NULL, ' +
  'injectRole TEXT NOT NULL DEFAULT \'system\', injectPosition TEXT NOT NULL DEFAULT \'head\', ' +
  'injectDepth INTEGER NOT NULL DEFAULT 0)';

export const SQL_CREATE_CONVERSATIONS: string = 'CREATE TABLE IF NOT EXISTS conversations (' +
  'id TEXT PRIMARY KEY, title TEXT NOT NULL, providerId TEXT NOT NULL DEFAULT \'\', ' +
  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, ' +
  'promptId TEXT NOT NULL DEFAULT \'\', assistantId TEXT NOT NULL DEFAULT \'\', ' +
  'locked INTEGER NOT NULL DEFAULT 0, titleSource TEXT NOT NULL DEFAULT \'\', ' +
  'favorite INTEGER NOT NULL DEFAULT 0, modelProviderId TEXT NOT NULL DEFAULT \'\', ' +
  'modelId TEXT NOT NULL DEFAULT \'\', webSearchOverride TEXT NOT NULL DEFAULT \'\', ' +
  'suggestions TEXT NOT NULL DEFAULT \'\')';
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
  'seq INTEGER DEFAULT NULL)';
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
  'key_pick_mode TEXT NOT NULL DEFAULT \'rotate\')';
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
    'sortOrder INTEGER NOT NULL DEFAULT 0)';
// skills v30 新建（2026-09-13 技能层，CRUD 在 SkillDb.ets）：一行一件技能。name = 技能名
//（唯一性不设约束——定位按 trim 逐字相等三态，多命中拒歧义）；description = 触发描述
//（进系统提示词「可用技能」清单，模型据此判断是否加载）；icon = sys.symbol 名字符串
//（**纯 UI，不进模型面**——候选集常量在 SkillText，改名只影响本机显示）；content = 技能
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
// 整库快照——记忆优化或记忆导入落库前自动存档，把「不可撤销」变成「可回退」。
// · libraryId = 'global'（全局库）/ 助手 id（助手库），与 memories / assistant_memories
//   的库判据同源（MEMORY_SCOPE_GLOBAL 常量；禁用 id 前缀判库，见 MemoryDb 头注释）；
// · kind = 'before_opt'（优化前存档）/ 'before_import'（导入前存档）——★ 2026-09-22 记忆导入笔
//   新增第三值：两类**非兜底槽共用**每库 ≤ MEMORY_SNAPSHOT_KEEP 份的配额与裁剪（按 kind 各裁
//   一份 = 导入槽永不清理 = 无界增长，故裁剪判据是 `kind != 兜底槽` 的否定式）/ 'before_restore'
//   （恢复前兜底，每库 ≤1 份、覆盖写）——保留规则见 MemoryDb 同名常量节；
// · note = 给人看的改动摘要（如「改写 3 条 · 合并 2 组」），兜底槽可为空串；
// · itemCount = 快照条目数（列表页不解析 payload 即可显示条数）；
// · payload = 该库全量条目的 JSON 数组串，元素形状 = MemoryRow 全列（含 sortOrder 三时间
//   字段——恢复必须原样写回，理由见 MemoryDb.restoreMemorySnapshot 注释）。
// ★ 列名用 `kind` **不用 `trigger`**——TRIGGER 是 SQLite 保留字，裸用有转义风险。
// ★ 不进 EXPORT_TABLES（本地后悔药不是跨设备资产，D8）；索引一枚 = 该库按类取行的列表主
//   路径（每库 ≤3+1 行，索引非性能必需，为「按库+类+时间」三键取行的意图留痕）
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
export const SQL_CREATE_KNOWLEDGE_ENTRIES: string = 'CREATE TABLE IF NOT EXISTS knowledge_entries (' +
  'id TEXT PRIMARY KEY, bookId TEXT NOT NULL DEFAULT \'\', title TEXT NOT NULL DEFAULT \'\', ' +
  'keywords TEXT NOT NULL DEFAULT \'\', content TEXT NOT NULL DEFAULT \'\', ' +
  'source TEXT NOT NULL DEFAULT \'user\', ' +
  'createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, ' +
  'sortOrder INTEGER NOT NULL DEFAULT 0)';
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
export const SQL_CREATE_TOKEN_USAGE_EVENTS: string = 'CREATE TABLE IF NOT EXISTS token_usage_events (' +
  'id TEXT PRIMARY KEY, conversationId TEXT NOT NULL DEFAULT \'\', ' +
  'messageId TEXT NOT NULL DEFAULT \'\', providerId TEXT NOT NULL DEFAULT \'\', ' +
  'modelId TEXT NOT NULL DEFAULT \'\', promptTokens INTEGER NOT NULL DEFAULT 0, ' +
  'completionTokens INTEGER NOT NULL DEFAULT 0, totalTokens INTEGER NOT NULL DEFAULT 0, ' +
  'durationMs INTEGER NOT NULL DEFAULT 0, firstTokenMs INTEGER NOT NULL DEFAULT 0, ' +
  'cachedTokens INTEGER NOT NULL DEFAULT 0, ' +
  'purpose TEXT NOT NULL DEFAULT \'chat\', createdAt INTEGER NOT NULL)';
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
