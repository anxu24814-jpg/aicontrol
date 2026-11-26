// Schema 维护域（2026-08-30 自 ChatDb 域级最小拆分——迁移钩子幂等化后 ChatDb 将超 400
// 红线：版本号/新装/迁移收拢本文件，ChatDb.doInit 依次调 ensureSchema → migrateSchema；
// ★ 2026-09-23 起建表 SQL 常量整块外迁 ChatDbSchema.ets——本件剔头 1189 已越 1200 硬线，
// 按技术债务清单建档候选缝先拆再落压缩笔改动，常量单一来源自此在彼件）。
// ★ 2026-10-27 治理批 C1 拆分笔：v1~v45 冻结历史迁移链（含 columnExists 与 v40 回填族）整块
// 外迁 ChatDbMigrateLegacy.ets——块体逐字搬迁零逻辑改动，migrateSchema 头部一行调用后续跑 v47 起。
// ★ 2026-10-06 拆分笔：v6~v45 逐版本语义注释整块外迁 docs/参考-ChatDb迁移版本史.md（纯
// 注释外迁 = 行数只减不加；见迁移区回指行）。表结构 v66：
// conversations + messages（v42 起含 coversToSeq 压缩摘要覆盖边界列，见版本史档 v42 条目）
// + providers（v2 起多服务商接线，
// 增 enabled/sortOrder 两列，CRUD 在 ProviderDb.ets；v3 起余额八列（七配置 + 查询文本，
// v8 补自定义头后九列），读写在
// ProviderBalanceDb.ets；v4 起协议 protocol + 自定义头 headers 两列；v5 起OpenAI 接口
// 形态 endpoint 列；v6 起会话提示词引用 promptId 列 + prompt_templates 提示词库表；
// v7 起 prompt_templates 注入配置三列 injectRole/injectPosition/injectDepth；v8 起余额
// 自定义头 balance_headers 列；v9 起会话助手引用 assistantId 列 + assistants 助手表；
// v16 起会话加密标记 locked 列；v17 起标题来源 titleSource 列；v19 起会话收藏 favorite
// 列；v20 起助手记忆两开关 memoryInject/memorySink 列；v22 起助手工具调用轮数上限
// toolStepLimit 列；v24 起会话级覆盖三列 modelProviderId/modelId/webSearchOverride；v25 起助手搜索结果条数
// searchResultCount 列；v30 起助手技能启用清单 skills 列〔语义与 tools 列刻意不同：'' =
// 空集合 = 默认不启用任何技能，见 SQL_CREATE_ASSISTANTS 注释〕；v40 起助手自定义列表序
// sortOrder 列（小者在前，0 起——语义与 providers.sortOrder 同款；v40 笔同时撤除读侧的
// 「内置两张恒列头部」硬钉，改由本列承载列表序，存量回填见版本史档 v40 条目）；v34 起会话消息后推荐
// suggestions 列 + 助手开场推荐 openers 列（语义与解析单落点见版本史档 v34 条目）+
// v38 起助手知识库启用清单 knowledge 列〔'' = 空集合 = 不启用任何知识库，与 skills 列
// 同义、与 tools 列反义〕；v45 起助手头像 avatar 列〔'' = 默认首字圆底 / 'text:<内容>' /
// 'image:<uri>'——编码解析与文件清理单源 AvatarSpec.ets，见版本史档 v45 条目〕）+ skills / skill_files（v30 新建——技能层两表：skills = 技能本体
// 一行一件，skill_files =
// 纯文本附件一行一件〔笔 1 建表零读写，笔 2 消费〕；CRUD 在 SkillDb.ets，纯函数在
// SkillText.ets）+ knowledge_books / knowledge_entries（v38 新建——知识库两表：
// knowledge_books = 库本体一行一本，knowledge_entries = 条目一行一条〔title/keywords/
// content 三字段，keywords 仅参与检索加权与展示不接触发逻辑；v39 补 source 来源标签
// 〔'user' / 'assistant'，只在 create 时定〕〕；v43 增 knowledge_files 附件表
// 〔一行一条目的纯文本附件，件名条目内唯一；只存文本、不进检索索引、不进注入块——
//   三条边界见建表 SQL 注释〕）；
// CRUD 在 KnowledgeDb.ets，
// 纯函数在 KnowledgeText.ets；用户可见名「知识库」）+ provider_models（v2 新建；v3 加 enabled 列 = 模型级启停；v15 加 caps_user_modified 列
// = 能力派生/覆盖标志——见迁移区 v15 注释；v21 加 favorite 列 = 模型收藏标记，本机语义
// 单家分享不携带；v27 加 price_config 列 = 价格 JSON 串，'' = 未配置，结构与解析单源 =
// CostStatsCalc.ets；v33 加 context_window 列 = 上下文窗口 token 数，0 = 未配置 = 跟随内置
// 参考值，非 0 = 用户覆盖——见版本史档 v33 条目，本笔无消费面）+
// provider_keys（v4 新建 = 多 Key 池，行读写
// 在 ProviderKeyDb.ets；★key 明文禁落 DB——表只存元数据，明文在 Asset，见 KeyStore）+
// token_usage_events（v18 新建 = token 用量账本，只追加，行读写与聚合在
// UsageStatsDb.ets；v26 起缓存命中列 cachedTokens；v27 起用途列 purpose）+
// memories（v20 新建 = 跨会话长期记忆表，行读写在 MemoryDb.ets；删会话不级联删记忆
// ——记忆是跨会话资产，conversationId 仅追溯；删助手级联置空 assistantId 不删行）+
// assistant_memories（v35 新建 = 助手级记忆库，行读写在 MemoryDb.ets；assistant_id =
// 归属语义，删助手同事务级联删行；与 memories 表「来源标注」语义刻意分离）+
// message_attachments（v23 新建 = 附件全量落盘第一轮，行读写与收敛在 AttachmentDb.ets；
// 一行一个已发送附件，级联删挂删会话/删助手两入口，**不进导出清单**——附件元数据将来
// 与文件本体同进同出，后置登记在 ExportImport 头注释）+
// price_templates（v28 新建 = 服务商级价格模板库，一行一套 serializePriceConfig 产出的
// 价格 JSON 串原文，CRUD 在 PriceTemplateDb.ets；随服务商删除级联清理；★ 不进任何
// 导出/迁移路径——决明 2026-09-11 拍板，技术债务登记见变更记录三百九十五节）+
// memory_snapshots（v41 新建 = 记忆优化历史快照库，一行一份整库快照，行读写在
// MemoryDb.ets；libraryId 判库、kind 分「优化前存档」与「导入前存档」（两类共用配额）与
// 「恢复前兜底」三值——完整值域与保留规则见建表 SQL 注释 + MemoryDb 同名常量节；
// ★ 不进导出清单——本地后悔药不是跨设备资产；删助手同事务级联删其助手库快照）+
// send_queue_items（v57 新建 = 排队中的用户消息待发表，一行一条；行读写单源
// ChatSendQueueDb.ets，建表 SQL 单源 ChatDbSchema.ets；行存在即 QUEUED，出队删行搭车
// prepareRun 单事务——库中永无 inFlight 歧义行；删会话/删助手两事务级联删行；★ 不进
// 导出清单——排队是发送意图非资产事实）+
// send_queue_state（v58 新建 = 会话级排队运行态持久真源，一行一会话；行读写单源
//   ChatSendQueueDb.ets；runState ACTIVE/PAUSED + pauseReason 四值，无行即 ACTIVE；删会话/
// 删助手两事务级联删；★ 不进导出清单）+
// mcp_servers（v59 新建 = MCP 服务器配置库一行一台；行读写单源 McpDb.ets、纯函数在
//   common/McpText.ets；★ 进 EXPORT_TABLES——用户搭建资产随备份走，头值明文恒不随
//   〔Asset 分流，见 SQL_CREATE_MCP_SERVERS 注释〕；assistants 表 v59 起加 mcpServers
//   勾选清单列——'' 含坏 JSON = 空集合 = 不启用任何服务器，语义照 skills/knowledge）。
// 版本号走 store.version（官方升降级姿势 = PRAGMA user_version 等价物；只加不改）。
// ★ 迁移两条铁律（2026-08-30 领导拍板「改幂等」，原实现两缺陷已修）：
// ①**逐级迁移**——每级迁移只把 version 升到本级（原 v1 分支一步写 DB_VERSION=3：v1 库
// 升级中断重跑会跳过 v2/v3 列补全 = 漏迁），中断后重跑从当前 version 续传；
// ②**迁移 SQL 幂等**——ALTER 前先查列存在（columnExists），中断重跑不报 duplicate
// column；CREATE 全用 IF NOT EXISTS 天然幂等。
// ③版本号升 D 时的三处同步义务（防漏迁）：建表 SQL 补新列（新装即最新）+ ensureSchema
// 标 DB_VERSION + 新增 if (db.version === D-1) 迁移分支（照逐级+幂等两条写）。
import { relationalStore } from '@kit.ArkData';
import {
  SQL_CREATE_ASSISTANTS, SQL_CREATE_ASSISTANT_MEMORIES, SQL_CREATE_ASSISTANT_MEMORIES_ASSISTANT_INDEX,
  SQL_CREATE_ATTACHMENT_REFS, SQL_CREATE_ATTACHMENT_REFS_ATTACH_INDEX, SQL_CREATE_ATTACHMENT_REFS_CONV_INDEX,
  SQL_CREATE_BRANCHES, SQL_CREATE_BRANCHES_CONV_INDEX,
  SQL_CREATE_CONVERSATIONS, SQL_CREATE_GENERATION_RUNS, SQL_CREATE_GENERATION_RUNS_CONV_INDEX,
  SQL_CREATE_GRAPH_CAPABILITY,
  SQL_CREATE_KNOWLEDGE_BOOKS, SQL_CREATE_KNOWLEDGE_ENTRIES,
  SQL_CREATE_KNOWLEDGE_ENTRIES_BOOK_INDEX, SQL_CREATE_KNOWLEDGE_FILES, SQL_CREATE_MCP_SERVERS,
  SQL_CREATE_MEMORIES,
  SQL_CREATE_MEMORIES_TIME_INDEX,
  SQL_CREATE_MEMORY_SNAPSHOTS, SQL_CREATE_MEMORY_SNAPSHOTS_INDEX, SQL_CREATE_MESSAGE_ATTACHMENTS,
  SQL_CREATE_MESSAGE_ATTACHMENTS_CONV_INDEX, SQL_CREATE_MESSAGE_ATTACHMENTS_MSG_INDEX,
  SQL_CREATE_MESSAGES, SQL_CREATE_MESSAGES_INDEX, SQL_CREATE_MESSAGES_SEQ_INDEX,
  SQL_CREATE_PRICE_TEMPLATES, SQL_CREATE_PROMPT_TEMPLATES, SQL_CREATE_PROVIDER_KEYS,
  SQL_CREATE_PROVIDER_KEYS_INDEX, SQL_CREATE_PROVIDER_MODELS, SQL_CREATE_PROVIDER_MODELS_INDEX,
  SQL_CREATE_PROVIDERS, SQL_CREATE_SKILLS, SQL_CREATE_SKILL_FILES, SQL_CREATE_SUMMARY_BINDINGS,
  SQL_CREATE_SUMMARY_BINDINGS_CONV_INDEX, SQL_CREATE_TOKEN_USAGE_CONV_INDEX,
  SQL_CREATE_TOKEN_USAGE_EVENTS, SQL_CREATE_TOKEN_USAGE_TIME_INDEX, SQL_CREATE_TOOL_FACTS,
  SQL_CREATE_TOOL_FACTS_RUN_INDEX, SQL_CREATE_HTTP_TEMPLATES, SQL_CREATE_WORKSPACE_FILES,
  SQL_CREATE_FOLDER_MOUNTS, SQL_CREATE_SEND_QUEUE_ITEMS, SQL_CREATE_SEND_QUEUE_STATE
} from './ChatDbSchema';
import { columnExists, migrateLegacyVersions } from './ChatDbMigrateLegacy';

// export（2026-09-12 为自检域 A1「store.version 与本常量一致」加出口；自检域 2026-09-20
// 全量退役后仍导出——各断言脚本按「export const DB_VERSION」形态钉住本行共五处，收回
// export 需同笔改钉，故留出口当只读单一来源）
// ★ v48（2026-10-01 方案-文件工作区-20261001）：+1 = workspace_files 一表（文件工作区
//   存储，方案档 §3.3）。表语义与 CRUD 域级单源 = WorkspaceDb.ets，建表 SQL 常量单源 =
//   ChatDbSchema.ets（零 import 避环——同 v47 判据）
// ★ v49（2026-10-02 任务书-工作区文件夹与模型目录工具）：workspace_files +dir 列（相对
//   工作区根的 / 分隔路径串，'' = 根；文件夹与目录工具笔的地基）。列语义单源 =
//   ChatDbSchema 建表串注释；零数据回填——存量行落默认 '' = 根，与 v48 物理平铺事实一致
// ★ v50（2026-10-04 文件夹段排序笔）：workspace_files +sortOrder 列（目录行自定义序，
//   管理页文件夹段长按拖拽的持久化键；只目录行消费、文件行恒 0 不消费；存量全 0 =
//   名称字典序兜底 = 升级前列表序零漂移）。列语义与写点单源 = WorkspaceDb.ets「目录排序
//   域」节 + ChatDbSchema 建表串注释；零数据回填（DEFAULT 0 即存量语义，与 v29 memories
//   同判据）
// ★ v51（2026-10-04 世界书关键词触发笔，任务书-世界书关键词触发-20261004）：两表五列——
//   knowledge_entries 补 injectRole/injectPosition/injectDepth/enabled 四列（条目级注入
//   配置与启用开关，三注入列与 prompt_templates v7 同形制）+ assistants 补
//   knowledgeAutoInject（助手级自动注入开关，**默认 0 关**——存量助手升级后不自动注入，
//   请求逐字节同升级前）。零数据回填（DEFAULT 即存量语义：条目全启用且无注入差异、
//   助手全关）；列义单源 = ChatDbSchema 建表串注释 + KnowledgeDb/AssistantDb 行接口注释
// ★ v52（2026-10-04 AI 配置服务商笔，任务书-AI配置服务商与安全输入-20261004）：providers
//   补 builtin 一列（内置服务商标记，1 = 内置 = 不可删只能停用；DEFAULT 0 = 存量与用户
//   新建行全非内置，升级后行为零变化）。**有数据回填**——12 组预置按「名称 + 地址仍是
//   预置原样」双等回填（与 seed 查重口径同构），字面量见下方 v52 迁移分支
// ★ v53（2026-10-04 方案-工作区识别文字-20261004）：workspace_files 补 ocr 六列（识别文本
//   / 引擎名 / 识别时刻 / 文件 mtime·size 指纹快照 / 校对时刻，全带默认值）。列义与覆盖即清
//   红线（六列禁进任何 insert/upsert 清单）单源 = ChatDbSchema 建表串注释；读写与指纹/
//   状态纯函数单源 = WorkspaceDbOcr.ets。零数据回填（DEFAULT 即「未识别」存量语义，v49 同
//   判据）。版本号按占号规则取执行时点现行值 52 + 1（§2.5——AI 配置服务商书已占 52）
// ★ v54（2026-10-07 会话轨迹视图 S0 数据层，任务书-会话轨迹视图-20261007 §3）：tool_facts
//   补 finishedAt 一列（工具事实的终态时刻毫秒；0 = 无终态时刻——未终态行与旧行）。零数据
//   回填（DEFAULT 0 即存量语义，v49 dir 同判据）；写点唯一 = MessageBranchDb.recordToolFact
//  （新建落 0、终态推进同址打 now、dispatch_intent 不动）；首个消费方 = 会话轨迹视图的工具
//   耗时口径（finishedAt − createdAt，0 → 不显示数字）
// ★ v55（2026-10-08 方案-文件夹挂载-20261008 笔 1「地基 + 管理面」）：新表 folder_mounts
//   一表（AI 文件夹挂载记录，方案 §3.6）。行读写单源 = MountDb.ets、纯函数在
//   MountUtil.ets、建表 SQL 常量单源 = ChatDbSchema.ets（零 import 避环——同 v48 判据）。
//   零数据回填（新表空集即存量语义）。★ 不进备份（授权记录存系统侧按设备隔离——方案
//   §3.6 备份排除）
// ★ v56（2026-10-08 M2 写面笔，决明拍板）：folder_mounts 拆 aiAccess 列——「允许 AI
//   使用」开关整面退役（想断访问直接移除挂载，双层门收敛为组卡开关单层门）。DROP
//   COLUMN 幂等守卫照铁律②；**零数据迁移**（列本就只读不消费语义，拆除即终态）。
//   SQLite DROP COLUMN 需 ≥3.35（API 26 基线远超）；列非主键无索引无约束，删之合法
// ★ v57（2026-10-17 排队插队施工总案 Q3「排队持久化」）：新表 send_queue_items 一表
//   （排队中的用户消息待发表；一行一条，会话级队列的持久真源）。行读写单源 =
//   ChatSendQueueDb.ets、建表 SQL 常量单源 = ChatDbSchema.ets（零 import 避环——同 v48
//   判据）。零数据回填（新表空集即存量语义；v57 前队列只在内存态）。出队删行搭车
//   prepareRun 单事务（MessageBranchDb.prepareRun，queueItemId 非空时 DELETE），**本表不
//   预写状态**——库中永无 inFlight 歧义行；删会话/删助手两事务各加一条级联 DELETE；★ 不进
//   EXPORT_TABLES（排队是发送意图非资产事实）。**判据宽容式含 57**（铁律③ + v33 起先例：
//   编辑窗口期的中间构建停在 57 且缺表的库，重跑要能进本分支补建）
// ★ v58（2026-10-17 排队暂停位落库笔）：新表 send_queue_state 一表（会话级排队运行态
//   持久真源——修「暂停后重启 / 退页 5s 空闲回收，队列恢复按 ACTIVE 自动续发」的暂停意图
//   丢失）。行读写单源 = ChatSendQueueDb.ets。零数据回填（新表空集 = 存量一律 ACTIVE，与
//   v58 前内存初值同义）。删会话/删助手两事务各加一条级联 DELETE；★ 不进 EXPORT_TABLES。
//   **判据宽容式含 58**（铁律③）
// ★ v59（2026-10-19 方案-MCP页施工方案 B2「数据层」）：**双动作迁移**——①新表 mcp_servers
//   一表（MCP 服务器配置库：name/url/enabled/headersJson 元数据/toolsJson 工具缓存/
//   lastSyncAt/lastError/createdAt，列义单源 = ChatDbSchema.SQL_CREATE_MCP_SERVERS 注释；
//   行读写单源 = McpDb.ets、纯函数 = common/McpText.ets）+ ②assistants 补 mcpServers 列
//   （助手勾选的 MCP 服务器 id 清单 JSON 串，'' 含坏 JSON = 空集合 = 不启用任何服务器，
//   语义照 skills〔v30〕/ knowledge〔v38〕第三、四例——**禁复用**任何既有列解析函数）。
//   零数据回填（新表空集即存量语义；DEFAULT '' 即「零勾选」存量语义）。★ **成本如实**：
//   v59 为双动作迁移（建表 + 加列），**非零额外迁移**。头值明文恒不进库（Asset 分流，
//   KeyStore 第九形态）。★ 进 EXPORT_TABLES（B2 同笔落）。**判据宽容式含 59**（铁律③ +
//   v33 起先例：编辑窗口期的中间构建停在 59 且缺表缺列的库，重跑要能进本分支补建补列）。
//   逐级：只写 59（铁律①）；ALTER 前 columnExists 守卫、CREATE IF NOT EXISTS 双幂等
//   （铁律②）。★ assistants 两墓碑列（toolStepLimit / searchResultCount）本笔零触碰——
//   原定「下次 assistants 结构性升版」偿还，本笔显式续期（技术债务清单登记，理由见变更
//   记录本笔节）
// ★ v60（2026-10-19 方案-MCP二期对标增强 C1）：mcp_servers 加两列——①authKind（认证方式
//   意图标记：'none' / 'bearer' / 'apiKey' / 'custom'，列义单源 =
//   ChatDbSchema.SQL_CREATE_MCP_SERVERS 注释）；②protocolVersion（广告协议版本：'' = 自动
//   协商，否则强制广告版本串，取值域单源 = McpRpc.MCP_VERSIONS_LEGAL）。**零数据回填**
//   （DEFAULT 'custom' / '' 即存量行为等价值：自定义头组 UI + 自动协商）。单级双列，照
//   v52 providers 加列范式；ALTER 前逐列 columnExists 守卫、只写 60（铁律①②）。★ 备份零
//   改动：导出侧 tableColumns() 动态列清单，新列自动随备份、旧备份缺列落 DEFAULT。
//   **判据宽容式含 60**（铁律③）
// ★ v61（2026-10-21 方案-引用功能全链路 U-C）：messages 加 quote_text 一列（用户消息的
//   引用全文快照；NULL = 无引用。列有意无约束——与 parentMessageId/seq 同款「无语义 =
//   NULL」；不用 NOT NULL DEFAULT '' 是因为空串与 NULL 语义分家：NULL = 从未有引用，
//   '' 不出现）。零数据回填（存量行全 NULL 即存量语义）；消费面 = 发送链 prepareRun
//   bucket 写入 + 读窗 IN 查询投影回放 + fork/图快照保真（组装层拼 blockquote 前缀，
//   content 列恒存用户原文）。列义单源 = ChatDbSchema 建表串注释；行接口 =
//   ChatDb.MessageRow.quoteText。ALTER 前 columnExists 守卫（铁律②）；判据宽容式含 61
//   （铁律③ + v33 起先例）；逐级：只写 61（铁律①）。★ 备份零改动（ExportImport 导出
//   SELECT * 自动随列、旧备份缺列落 DEFAULT NULL 存量语义）
// ★ v62（2026-10-25 控制台助手退役与合并笔，决明拍板「合并」）：**双动作数据迁移**——
//   ①控制台助手名下会话改指默认助手（历史对话全保留，后续对话走默认助手的模型与工具）；
//   ②删 assistants 表 assistant-console 行（控制台助手整体退役：原独占工具域同笔开放给
//   全部助手，set_app_preference 写件退役、seed 迁移机制与 CONSOLE_ASSISTANT_PROMPT 同笔
//   拆除，沿革 = docs/变更记录.md 对应节）。两 id 字面量照 MIGRATE_ASSISTANT_* 先例（本件
//   禁 import AssistantDb——模块环坑50）。幂等：UPDATE / DELETE 命中零行均为合法重跑终态
//   （铁律②；无 ALTER 无 CREATE）；判据宽容式含 62（铁律③）；逐级：只写 62（铁律①）。
//   ★ 备份零改动：导出清单本就不含 assistants 内置行判定，会话行 assistantId 改值后随
//   备份走（新值在旧包导入 = 悬空行回退系统提示词，既有兜底语义）
// ★ v63（2026-10-26 方案-知识库触发精度-20261025 第一档）：knowledge_entries 加四列——
//   matchCase / matchWhole（0/1 布尔列，默认 0 = 与旧匹配行为逐字一致）/ priority（0~9999
//   默认 100，排序第一键降序、同值回落原四键 = 存量顺序零变化）/ scanDepth（1~20 默认 8
//   = 退役常量 KNOWLEDGE_SCAN_MESSAGES 同值）。**零数据回填**（四列 DEFAULT 即旧行为等价值
//   ——升级前后请求逐字节一致，方案 §一）。列义与值域单源 = ChatDbSchema v63 注释 +
//   KnowledgeText 常量族。ALTER 前逐列 columnExists 守卫（铁律②）；判据宽容式含 63（铁律③
//   + v33 起先例：编辑窗口期的中间构建停在 63 且列未补齐的库，重跑要能进本分支补列）；逐级：
//   只写 63（铁律①）。★ 备份零改动：导出 SELECT * 自动随列、旧备份缺列落 DEFAULT（方案 §5.3）。
//   ★ 降级注意（方案 R3）：v63 库被旧包读取会被「version > DB_VERSION」硬闸拒绝——回退真实
//   路径 = 卸载重装 + 从 v62 备份恢复
// ★ v64（2026-11-14 DS 全家桶接入批 S2，任务书-DS全家桶接入-20261114 §6-S2）：messages 加
//   server_tools 一列（assistant 行的 DeepSeek 服务端工具原样 JSON 串
//   {"server_tool_calls":…,"annotations":…}——官方末帧两字段合体，回传保真禁截断禁重排；
//   NULL = 非官方档轮/无服务端步骤。列有意无约束——与 quote_text 同款「无语义 = NULL」，
//   不用 NOT NULL DEFAULT '' 是因为空串与 NULL 语义分家）。零数据回填（存量行全 NULL 即
//   存量语义）；消费面 = 轮收口条件写键（MessageBranchDb.writeNodeServerTools——终答
//   GraphFinishInput.serverTools / 中间轮提交口从 stampTarget 读）+ 回放投影
//   （chatMessagesFromRows 行投影）+ 请求回传（buildRequestHistory → composeOpenAiBody
//   server_tool_calls 仅官方档轮输出）。列义单源 = ChatDbSchema 建表串注释；行接口 =
//   ChatDb.MessageRow.serverTools。ALTER 前 columnExists 守卫（铁律②）；判据宽容式含 64
//   （铁律③ + v33 起先例）；逐级：只写 64（铁律①）。★ 备份零改动（导出 SELECT * 自动随列、
//   旧备份缺列落 DEFAULT NULL 存量语义）
// ★ v66（2026-11-17 整体退役加密会话笔，决明指令「整体退役加密会话」）：**数据清零迁移**——
//   conversations.locked 退役为墓碑（功能全链撤除、产品码零读写，列定义保留不删，理由见
//   ChatDbSchema 建表串前注释），存量 locked=1 行一次性清零 = 「原加密会话自此与普通会话完全
//   同权」（可见性/检索/记忆沉淀三面全部归一）。零 schema 变更（无 ALTER 无 CREATE）；幂等：
//   UPDATE 命中零行为合法重跑终态（铁律②）；判据宽容式含 66（铁律③）；逐级：只写 66
//  （铁律①）。★ 降级注意：v66 库被旧包读取会被版本闸拒绝（同 v63 先例），回退真实路径 =
//   revert 本笔重装 + 从备份恢复；清零不可逆，但墓碑列语义已消失、回退后这些会话只是「未
//   加密」，无数据损失。
export const DB_VERSION: number = 66;

// v46（2026-09-26 消息架构整合笔2——分支存储与兼容准备，任务书-消息架构整合笔2-分支存储
// 与兼容准备-20260926 执行）：图侧 schema 与双层降级守卫（J2/J4，隔离库验证笔——**本笔
// 零构图零图写**，生产会话不进图侧表，总闸 J0）：
// ①建图侧六表——branches（分支树：head+parent 链真源，headMessageId 可空 = 无行会话
//   head 语义在存储层成立）/ generation_runs（run 持久化：笔1 词表 runId 升持久主键即
//   同一身份不重编号，revision 乐观并发 + checkpoint 检查点 + 终态诊断引用）/
//   tool_facts（工具事实四态机：prepared → dispatch_intent → result_confirmed / failed，
//   派发前先提交意图）/ summary_bindings（摘要绑定：稳定节点范围，coversToSeq 可空 =
//   「覆盖边界不可证」禁裁剪标记）/ attachment_refs（图侧附件引用，未来归属真源）/
//   graph_capability（单行图能力标记——双层守卫第二层持久真源）；
// ②三表补列——messages 补图节点身份五列（parentMessageId/runId/ownerAssistantId/
//   stepIndex/origin，正文仍在 messages 不另建第二份正文仓）；conversations 补
//   activeBranchId + migrateState（会话格式态两值 graph/legacy——唯一路由真源，判据 =
//   ChatContextSource.conversationWritableRoute「非 graph 即墓碑」；★ 2026-09-26 旧会话
//   墓碑笔：原三态机与迁移器随迁移机制整件退役）；token_usage_events
//   补账本幂等身份四列（runId/attemptId/branchId/requestId——请求级去重键冻结规则供笔3）；
// ③graph_capability 写 level 1（schema 已备、图未开启——本包支持上限
//   GRAPH_CAPABILITY_SUPPORTED = 1，笔3 开图写升 2 后本笔构建拒绝初始化 = fail-closed）。
// **无数据回填**（新列 DEFAULT 即 legacy 存量语义；存量值冻结不再维护、不重建表改约束
// ——J7）。★ 索引六枚：branches_conv / generation_runs_conv / tool_facts_run /
// summary_bindings_conv / attachment_refs_conv / attachment_refs_attach（graph 库的主查询
// 路径——构图迁移与路径读，随表建）。
// ★ ExportImport 零改动（J8：生产备份格式切换在笔3——图侧表不进 EXPORT_TABLES，本笔
// 只做隔离库证据；旧备份导入为「默认分支」的图级语义在笔3 接线时兑现，仓储层已有
// importConversationGraph 供隔离库验证）。
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫、CREATE IF NOT EXISTS 天然幂等、
// capability 写行为 INSERT OR IGNORE 幂等且只补缺不降级（★ 2026-09-26 自检位B 修复：原
// OR REPLACE 在已升级库每次冷启动重入 v46 分支时把笔3 写入的 level 2 覆写回 1）。
// ★ 双层降级守卫（J2，readGraphCapabilityLevel / verifyDbOpenable——初始化维护**之前**
// 调用，落点 ChatDb.doInit）：①store.version 高于本包 DB_VERSION → 拒绝；②graph_capability
// 表 level 高于 GRAPH_CAPABILITY_SUPPORTED → 拒绝。命中即抛错（doInit 捕获返假 → UI
// 「数据库初始化失败」可观察），不进迁移/维护、不拿句柄读写——笔2 包不懂生产 graph，
// 图一旦开启必须拒绝服务（含维护读写），不能正常降级使用。仅 DB 版本守卫不够（笔3 可在
// 同一 DB 版本上启用 graph）。已发布旧包不含守卫，不笼统许诺旧包对新库零写（总纲§6）。

// 双层守卫·第二层支持上限（本包理解的最高图能力级）：2 = 图已开启（★ 2026-09-26 消息
// 架构整合笔3 S5 自 1 升 2——本包接管图态库；笔2 包常量仍 1，其构建对 capability 2 的库
// 拒绝初始化 = 预期 fail-closed〔W12②〕）。库内 level 升 2 的唯一写点 =
// writeGraphCapabilityLevel，时点契约 = 图会话落库同拍（调用方
// ChatContextSource.bornGraphConversation / ExportImport.importGraphDomain）。值域语义
// 见 v46 注释。
export const GRAPH_CAPABILITY_SUPPORTED: number = 2;
// graph_capability 单行 id（恒此值；建库/迁移分支 INSERT OR IGNORE 补缺、升格写点
// writeGraphCapabilityLevel 带只升不降守卫）
const GRAPH_CAPABILITY_ROW_ID: string = 'graph';

// 读图能力级（守卫②读侧；表不存在 = 0——旧升级库在 v46 前无此表，守卫必须在迁移**前**
// 跑，故「表读不到」是合法初态非错误；查询异常同样按 0 兜底并留痕——守卫只对该「拒绝」
// 负责，不因探测失败误伤正常旧库）。★ 2026-09-27 订正 LB-6：原注释「返回 -1 = 值域脏值」
// 为早期设计残留，实现从不返回 -1——读到的 level 原样透出，高于支持值由调用方
// verifyDbOpenable 的「> SUPPORTED 即拒」判据处置
export async function readGraphCapabilityLevel(db: relationalStore.RdbStore): Promise<number> {
  let result: relationalStore.ResultSet;
  try {
    result = await db.querySql('SELECT level FROM graph_capability WHERE id = ?',
      [GRAPH_CAPABILITY_ROW_ID]);
  } catch (e) {
    return 0; // 表不存在/查询失败 = 能力标记不可得 = 旧库初态，放行（进迁移链建表）
  }
  try {
    if (!result.goToNextRow() || result.isColumnNull(result.getColumnIndex('level'))) {
      return 0;
    }
    return result.getLong(result.getColumnIndex('level'));
  } finally {
    result.close();
  }
}

// 写图能力级（2026-09-26 消息架构整合笔3 新增，K2——capability 写 2 的唯一写点；调用方 =
// ChatContextSource.bornGraphConversation / GraphTransfer.importGraphDomain，时点契约 =
// **图会话落库同拍**）。幂等写（or REPLACE 形态携带只升不降守卫——v46 建库/迁移分支的补缺
// 写已改 INSERT OR IGNORE，见彼处）；只许升不许
// 降——level < 库内现值直接抛错（graph 会话在场时降标记会制造「图开着而守卫标记降级」
// 的漏洞，即 K2 判据「不允许已构图库仍标低级」的反向保护）
export async function writeGraphCapabilityLevel(db: relationalStore.RdbStore,
  level: number): Promise<void> {
  const current: number = await readGraphCapabilityLevel(db);
  if (level < current) {
    throw new Error('图能力级只升不降：库内现级 ' + current + '，拒绝写到 ' + level);
  }
  await db.executeSql('INSERT OR REPLACE INTO graph_capability (id, level) VALUES (?, ?)',
    [GRAPH_CAPABILITY_ROW_ID, level]);
}

// 双层守卫（J2，初始化维护之前调用——ChatDb.doInit 落点；命中即抛中文错误，由 doInit
// 捕获返假 → UI 可观察，不进 ensureSchema/migrateSchema、不给句柄）。守卫①版本闸 +
// 守卫②能力闸。错误文案面向排障（hilog 面），不直接上 UI——UI 统一按「数据库初始化
// 失败」呈报（与既有 doInit 失败路径同语义）
export async function verifyDbOpenable(db: relationalStore.RdbStore): Promise<void> {
  if (db.version > DB_VERSION) {
    throw new Error('数据库版本 ' + db.version + ' 高于本包支持版本 ' + DB_VERSION +
      '（疑为更高版本应用的数据），已拒绝初始化以防结构破坏');
  }
  const level: number = await readGraphCapabilityLevel(db);
  if (level > GRAPH_CAPABILITY_SUPPORTED) {
    throw new Error('数据库图能力级 ' + level + ' 高于本包支持级 ' + GRAPH_CAPABILITY_SUPPORTED +
      '（该库已开启本包不支持的图模型），已拒绝初始化以防读写破坏新图');
  }
}

// ★ v6~v45 逐版本迁移语义唯一权威 = docs/参考-ChatDb迁移版本史.md（2026-10-06 拆分笔
// 自本件外迁——历史越 1200 硬线，纯注释外迁属「行数只减不加」的合法瘦身；全仓「见
// ChatDbMigrate vXX 注释」式引用经本行中转可达）。v46 起版本语义照旧记于本文件头段
// （与 DB_VERSION 同址）——新版本迁移落码在头段追加，不进该文档，单一来源不双写

// 新装建表（version === 0——原 ChatDb doInit 分支整体搬迁；CREATE IF NOT EXISTS 天然
// 幂等：中断重跑安全，重跑建的始终是当前全列结构，然后直接标当前 DB_VERSION）
export async function ensureSchema(db: relationalStore.RdbStore): Promise<void> {
  if (db.version !== 0) {
    return;
  }
  await db.executeSql(SQL_CREATE_CONVERSATIONS);
  await db.executeSql(SQL_CREATE_MESSAGES);
  await db.executeSql(SQL_CREATE_PROVIDERS);
  await db.executeSql(SQL_CREATE_PROVIDER_MODELS);
  await db.executeSql(SQL_CREATE_PROVIDER_KEYS);
  await db.executeSql(SQL_CREATE_PROMPT_TEMPLATES);
  await db.executeSql(SQL_CREATE_ASSISTANTS);
  await db.executeSql(SQL_CREATE_TOKEN_USAGE_EVENTS);
  await db.executeSql(SQL_CREATE_MEMORIES);
  await db.executeSql(SQL_CREATE_ASSISTANT_MEMORIES);
  await db.executeSql(SQL_CREATE_MESSAGES_INDEX);
  await db.executeSql(SQL_CREATE_MESSAGES_SEQ_INDEX);
  await db.executeSql(SQL_CREATE_PROVIDER_MODELS_INDEX);
  await db.executeSql(SQL_CREATE_PROVIDER_KEYS_INDEX);
  await db.executeSql(SQL_CREATE_TOKEN_USAGE_CONV_INDEX);
  await db.executeSql(SQL_CREATE_TOKEN_USAGE_TIME_INDEX);
  await db.executeSql(SQL_CREATE_MEMORIES_TIME_INDEX);
  await db.executeSql(SQL_CREATE_ASSISTANT_MEMORIES_ASSISTANT_INDEX);
  await db.executeSql(SQL_CREATE_MEMORY_SNAPSHOTS);
  await db.executeSql(SQL_CREATE_MEMORY_SNAPSHOTS_INDEX);
  await db.executeSql(SQL_CREATE_MESSAGE_ATTACHMENTS);
  await db.executeSql(SQL_CREATE_MESSAGE_ATTACHMENTS_MSG_INDEX);
  await db.executeSql(SQL_CREATE_MESSAGE_ATTACHMENTS_CONV_INDEX);
  await db.executeSql(SQL_CREATE_PRICE_TEMPLATES);
  await db.executeSql(SQL_CREATE_SKILLS);
  await db.executeSql(SQL_CREATE_SKILL_FILES);
  await db.executeSql(SQL_CREATE_KNOWLEDGE_BOOKS);
  await db.executeSql(SQL_CREATE_KNOWLEDGE_ENTRIES);
  await db.executeSql(SQL_CREATE_KNOWLEDGE_ENTRIES_BOOK_INDEX);
  await db.executeSql(SQL_CREATE_KNOWLEDGE_FILES);
  // v46 图侧六表与六索引（建表 SQL 注释与语义见 ChatDbSchema 图侧域；level 1 = schema
  // 已备图未开启——新装即写，与 v46 迁移分支升级路径同终态）
  await db.executeSql(SQL_CREATE_BRANCHES);
  await db.executeSql(SQL_CREATE_BRANCHES_CONV_INDEX);
  await db.executeSql(SQL_CREATE_GENERATION_RUNS);
  await db.executeSql(SQL_CREATE_GENERATION_RUNS_CONV_INDEX);
  await db.executeSql(SQL_CREATE_TOOL_FACTS);
  await db.executeSql(SQL_CREATE_TOOL_FACTS_RUN_INDEX);
  await db.executeSql(SQL_CREATE_SUMMARY_BINDINGS);
  await db.executeSql(SQL_CREATE_SUMMARY_BINDINGS_CONV_INDEX);
  await db.executeSql(SQL_CREATE_ATTACHMENT_REFS);
  await db.executeSql(SQL_CREATE_ATTACHMENT_REFS_CONV_INDEX);
  await db.executeSql(SQL_CREATE_ATTACHMENT_REFS_ATTACH_INDEX);
  await db.executeSql(SQL_CREATE_GRAPH_CAPABILITY);
  await db.executeSql("INSERT OR IGNORE INTO graph_capability (id, level) VALUES ('graph', 1)");
  // v47 HTTP 请求模板表（批 3 笔 6；表语义与 CRUD 单源 HttpTemplateDb.ets、建表 SQL 单源
  // ChatDbSchema——新装即建，与迁移分支升级路径同终态）
  await db.executeSql(SQL_CREATE_HTTP_TEMPLATES);
  // v48 文件工作区表（方案-文件工作区-20261001；表语义与 CRUD 单源 WorkspaceDb.ets、建表
  // SQL 单源 ChatDbSchema——新装即建，与迁移分支升级路径同终态）
  await db.executeSql(SQL_CREATE_WORKSPACE_FILES);
  // v55 文件夹挂载表（方案-文件夹挂载-20261008；表语义与行读写单源 MountDb.ets、建表
  // SQL 单源 ChatDbSchema——新装即建，与迁移分支升级路径同终态）
  await db.executeSql(SQL_CREATE_FOLDER_MOUNTS);
  // v57 排队消息表（排队插队施工总案 Q3；表语义与行读写单源 ChatSendQueueDb.ets、建表
  // SQL 单源 ChatDbSchema——新装即建，与迁移分支升级路径同终态）
  await db.executeSql(SQL_CREATE_SEND_QUEUE_ITEMS);
  // v58 排队运行态表（暂停位落库笔；同上单源——新装即建，与迁移分支升级路径同终态）
  await db.executeSql(SQL_CREATE_SEND_QUEUE_STATE);
  // v59 MCP 服务器表（方案-MCP页施工方案 B2；表语义与行读写单源 McpDb.ets、建表 SQL 单源
  // ChatDbSchema——新装即建，与迁移分支升级路径同终态）
  await db.executeSql(SQL_CREATE_MCP_SERVERS);
  db.version = DB_VERSION;
}

// 逐级迁移（只加不改；每级完成只升本级 version——中断后重跑从当前 version 续传，铁律①）：
export async function migrateSchema(db: relationalStore.RdbStore): Promise<void> {
  // v1~v45 历史迁移链已整块外迁 ChatDbMigrateLegacy.ets（2026-10-27 C1 拆分笔——块体逐字
  // 搬迁零逻辑改动，链尾写 46 后回此处续跑；v1→v2/v2→v3 首两级描述随链在新件头注释）
  await migrateLegacyVersions(db);

  // v46/v47 → v47（2026-10-01 方案-HTTP工具完善 批 3 笔 6「请求复用面」）：新增
  // http_templates 一表（请求模板存储）。表语义与 CRUD 域级单源 = HttpTemplateDb.ets，
  // 建表 SQL 单源 = ChatDbSchema（零 import 避环——本文件引 HttpTemplateDb 会成
  // ChatDb → ChatDbMigrate → HttpTemplateDb → ChatDb 环，MIGRATE_ASSISTANT 常量先例同
  // 判据），CREATE IF NOT EXISTS 幂等（铁律②）；零数据回填、零 ALTER。中断重跑安全：
  // 判据宽容式含 47（v33 起先例），重跑时建表语句天然幂等
  // ★ 2026-10-27 C1 补注：「零 import 避环」的约束范围 = 禁 import 业务 CRUD 件（本件引
  // HttpTemplateDb 会成 ChatDb 环），并非禁一切 import——import ChatDbSchema（2026-09-23 起）
  // 与 ChatDbMigrateLegacy（2026-10-27 起，叶子件不 import 本件）均单向无环
  if (db.version === 46 || db.version === 47) {
    await db.executeSql(SQL_CREATE_HTTP_TEMPLATES);
    if (db.version === 46) {
      db.version = 47;
    }
  }
  // v47/v48 → v48（2026-10-01 方案-文件工作区-20261001）：新增 workspace_files 一表（文件
  // 工作区存储——助手写入/列出/读取三工具与管理页共用的表）。表语义与 CRUD 域级单源 =
  // WorkspaceDb.ets，建表 SQL 单源 = ChatDbSchema（零 import 避环——v47 同判据），CREATE
  // IF NOT EXISTS 幂等（铁律②）；零数据回填、零 ALTER（表自空起步——工作区文件不预置）。
  // **判据宽容式含 48**（铁律③ + v33 起先例：功能笔编辑窗口期的中间构建被侧载到真机时，
  // 停在 48 且本表缺失的库若只写 `=== 47`，本分支永不进 → 工作区查询直接抛 SQL 错）。
  // 中断重跑安全：重跑时建表语句天然幂等
  if (db.version === 47 || db.version === 48) {
    await db.executeSql(SQL_CREATE_WORKSPACE_FILES);
    if (db.version === 47) {
      db.version = 48;
    }
  }
  // v48/v49 → v49（2026-10-02 任务书-工作区文件夹与模型目录工具）：workspace_files 加
  // dir 列（相对工作区根的 / 分隔路径串，'' = 根）。ALTER 前 columnExists 守卫（铁律②
  // ——中断重跑不报 duplicate column）；零数据回填——存量行 dir 落默认 '' = 根，与
  // 「v48 物理平铺、localPath 恒 workspace/<fileId>.<ext>」的物理事实一致，无需搬文件。
  // **判据宽容式含 49**（铁律③ + v33 起十五连先例：编辑窗口期的中间构建停在 49 且缺列
  // 的库，重跑要能进本分支补列）。逐级：只写 49（铁律①）
  if (db.version === 48 || db.version === 49) {
    if (!(await columnExists(db, 'workspace_files', 'dir'))) {
      await db.executeSql("ALTER TABLE workspace_files ADD COLUMN dir TEXT NOT NULL DEFAULT ''");
    }
    if (db.version === 48) {
      db.version = 49;
    }
  }
  // v49/v50 → v50（2026-10-04 文件夹段排序笔）：workspace_files 加 sortOrder 列（目录行
  // 自定义序；语义与写点见上方 v50 版本注释与 ChatDbSchema 建表串注释）。ALTER 前
  // columnExists 守卫（铁律②——中断重跑不报 duplicate column）；**零数据回填**（DEFAULT 0
  // 即存量语义：存量目录行全 0 时派生层按名称字典序兜底 = 升级前列表序逐字节一致，
  // 与 v29 memories.sortOrder 同判据，无需 v40 式回填）。**判据宽容式含 50**（铁律③ +
  // v33 起十六连先例：编辑窗口期的中间构建停在 50 且缺列的库，重跑要能进本分支补列）。
  // 逐级：只写 50（铁律①）
  if (db.version === 49 || db.version === 50) {
    if (!(await columnExists(db, 'workspace_files', 'sortOrder'))) {
      await db.executeSql('ALTER TABLE workspace_files ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0');
    }
    if (db.version === 49) {
      db.version = 50;
    }
  }
  // v50/v51 → v51（2026-10-04 世界书关键词触发笔）——knowledge_entries 补注入三列与启用
  // 开关（条目级配置，与 prompt_templates v7 注入三列同形制）+ assistants 补
  // knowledgeAutoInject（默认 0 关 = 存量助手升级后不自动注入，请求逐字节同升级前）。
  // ALTER 前 columnExists 守卫（铁律②——中断重跑不报 duplicate column）；**零数据回填**
  //（DEFAULT 即存量语义，v39 source / v45 avatar 同判据）。**判据宽容式含 51**（铁律③ +
  // v33 起十七连先例：编辑窗口期的中间构建停在 51 且缺列的库，重跑要能进本分支补列）。
  // 逐级：只写 51（铁律①）
  if (db.version === 50 || db.version === 51) {
    if (!(await columnExists(db, 'knowledge_entries', 'injectRole'))) {
      await db.executeSql(
        "ALTER TABLE knowledge_entries ADD COLUMN injectRole TEXT NOT NULL DEFAULT 'system'");
    }
    if (!(await columnExists(db, 'knowledge_entries', 'injectPosition'))) {
      await db.executeSql(
        "ALTER TABLE knowledge_entries ADD COLUMN injectPosition TEXT NOT NULL DEFAULT 'head'");
    }
    if (!(await columnExists(db, 'knowledge_entries', 'injectDepth'))) {
      await db.executeSql('ALTER TABLE knowledge_entries ADD COLUMN injectDepth INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'knowledge_entries', 'enabled'))) {
      await db.executeSql('ALTER TABLE knowledge_entries ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1');
    }
    if (!(await columnExists(db, 'assistants', 'knowledgeAutoInject'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN knowledgeAutoInject INTEGER NOT NULL DEFAULT 0');
    }
    if (db.version === 50) {
      db.version = 51;
    }
  }
  // v51/v52 → v52（2026-10-04 AI 配置服务商笔，任务书-AI配置服务商与安全输入-20261004）：
  // providers 加 builtin 列（内置服务商标记，语义见上方 v52 版本注释）。ALTER 前
  // columnExists 守卫（铁律②——中断重跑不报 duplicate column）。★ 存量回填：12 组预置按
  // 「名称 + 地址仍是预置原样」双等判据回填（与 ProviderPresetSeed 查重口径同构——用户改名
  // /改址过的预置行不标内置，防把用户深度定制过的行锁进不可删态）；**12 组字面量写死、禁
  // import ProviderCatalog**（ChatDbMigrate ← ChatDb ← ProviderDb ← ProviderCatalog 家族添
  // 边即埋环雷，照 backfillAssistantSortOrder 的「字面量不 import」纪律，MIGRATE_ASSISTANT_*
  // 同款），且为**历史快照**——预置清单后续变更不随动（只锁「出厂原样」的行）；SQL 全字面量
  // 幂等（中断重跑安全，重复执行零副作用）。**判据宽容式含 52**（铁律③ + v33 起先例）。
  // 逐级：只写 52（铁律①）
  if (db.version === 51 || db.version === 52) {
    if (!(await columnExists(db, 'providers', 'builtin'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN builtin INTEGER NOT NULL DEFAULT 0');
    }
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = 'DeepSeek' AND baseUrl = 'https://api.deepseek.com/v1'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = '月之暗面' AND baseUrl = 'https://api.moonshot.cn/v1'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = '智谱 GLM' AND baseUrl = 'https://open.bigmodel.cn/api/paas/v4'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = '火山方舟' AND baseUrl = 'https://ark.cn-beijing.volces.com/api/v3'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = '阿里云百炼' AND baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = '硅基流动' AND baseUrl = 'https://api.siliconflow.cn/v1'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = 'OpenAI' AND baseUrl = 'https://api.openai.com/v1'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = 'Anthropic' AND baseUrl = 'https://api.anthropic.com'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = 'Gemini' AND baseUrl = 'https://generativelanguage.googleapis.com'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = 'OpenRouter' AND baseUrl = 'https://openrouter.ai/api/v1'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = 'MiniMax' AND baseUrl = 'https://api.minimaxi.com/v1'");
    await db.executeSql("UPDATE providers SET builtin = 1 WHERE name = 'OpenCode' AND baseUrl = 'https://opencode.ai/zen/v1'");
    if (db.version === 51) {
      db.version = 52;
    }
  }
  // v52/v53 → v53（2026-10-04 方案-工作区识别文字-20261004）：workspace_files 加 ocr 六列
  // （识别文本 / 引擎名 / 识别时刻 / 文件 stat 指纹快照两列 / 校对时刻；语义见上方 v53 版本
  // 注释与 ChatDbSchema 建表串注释）。ALTER 前逐列 columnExists 守卫（铁律②——中断重跑
  // 不报 duplicate column）；**零数据回填**（DEFAULT 即「未识别」存量语义，v49 dir 同判据）。
  // **判据宽容式含 53**（铁律③ + v33 起先例：编辑窗口期的中间构建停在 53 且缺列的库，重跑
  // 要能进本分支补列）。逐级：只写 53（铁律①）
  if (db.version === 52 || db.version === 53) {
    if (!(await columnExists(db, 'workspace_files', 'ocrText'))) {
      await db.executeSql("ALTER TABLE workspace_files ADD COLUMN ocrText TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'workspace_files', 'ocrEngine'))) {
      await db.executeSql("ALTER TABLE workspace_files ADD COLUMN ocrEngine TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'workspace_files', 'ocrAt'))) {
      await db.executeSql('ALTER TABLE workspace_files ADD COLUMN ocrAt INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'workspace_files', 'ocrFileMtime'))) {
      await db.executeSql('ALTER TABLE workspace_files ADD COLUMN ocrFileMtime INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'workspace_files', 'ocrFileSize'))) {
      await db.executeSql('ALTER TABLE workspace_files ADD COLUMN ocrFileSize INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'workspace_files', 'ocrEditedAt'))) {
      await db.executeSql('ALTER TABLE workspace_files ADD COLUMN ocrEditedAt INTEGER NOT NULL DEFAULT 0');
    }
    if (db.version === 52) {
      db.version = 53;
    }
  }
  // v53/v54 → v54（2026-10-07 会话轨迹视图 S0 数据层）：tool_facts 加 finishedAt 列（语义
  // 见上方 v54 版本注释与 ChatDbSchema 建表串注释）。ALTER 前 columnExists 守卫（铁律②——
  // 中断重跑不报 duplicate column）；**零数据回填**（DEFAULT 0 即「无终态时刻」存量语义，
  // v49 dir 同判据）。**判据宽容式含 54**（铁律③ + v33 起先例：编辑窗口期的中间构建停在 54
  // 且缺列的库，重跑要能进本分支补列）。逐级：只写 54（铁律①）
  if (db.version === 53 || db.version === 54) {
    if (!(await columnExists(db, 'tool_facts', 'finishedAt'))) {
      await db.executeSql('ALTER TABLE tool_facts ADD COLUMN finishedAt INTEGER NOT NULL DEFAULT 0');
    }
    if (db.version === 53) {
      db.version = 54;
    }
  }
  // v54/v55 → v55（2026-10-08 文件夹挂载笔 1）：新建 folder_mounts 表（语义见上方 v55 版本
  // 注释与 ChatDbSchema 建表串注释）。CREATE IF NOT EXISTS 天然幂等（铁律②——中断重跑不报
  // 表已存在）；**零数据回填**（新表空集即存量语义）。**判据宽容式含 55**（铁律③ + v33 起
  // 先例：编辑窗口期的中间构建停在 55 且缺表的库，重跑要能进本分支补建）。逐级：只写 55
  if (db.version === 54 || db.version === 55) {
    await db.executeSql(SQL_CREATE_FOLDER_MOUNTS);
    if (db.version === 54) {
      db.version = 55;
    }
  }
  // v55/v56 → v56（2026-10-08 M2 写面笔）：folder_mounts 拆 aiAccess 列（决明拍板「允许
  // AI 使用」开关整面退役，语义见上方 v56 版本注释）。DROP 前 columnExists 守卫（铁律②
  // ——中断重跑不报 no such column；新装库建表串已无本列，守卫天然跳过）。**零数据迁移**
  //（列值不再被任何面消费）。**判据宽容式含 56**（铁律③ + v33 起先例：编辑窗口期的中间
  // 构建停在 56 且列仍在的库，重跑要能进本分支补拆）。逐级：只写 56（铁律①）
  if (db.version === 55 || db.version === 56) {
    if (await columnExists(db, 'folder_mounts', 'aiAccess')) {
      await db.executeSql('ALTER TABLE folder_mounts DROP COLUMN aiAccess');
    }
    if (db.version === 55) {
      db.version = 56;
    }
  }
  // v56/v57 → v57（2026-10-17 排队插队施工总案 Q3「排队持久化」）：新建 send_queue_items
  // 表（语义见上方 v57 版本注释与 ChatDbSchema 建表串注释）。CREATE IF NOT EXISTS 天然幂等
  //（铁律②——中断重跑不报表已存在）；**零数据回填**（新表空集即存量语义：v57 前队列只在
  // 内存态，进程退出即失）；零 ALTER。**判据宽容式含 57**（铁律③ + v33 起先例：编辑
  // 窗口期的中间构建停在 57 且缺表的库，重跑要能进本分支补建）。逐级：只写 57（铁律①）
  if (db.version === 56 || db.version === 57) {
    await db.executeSql(SQL_CREATE_SEND_QUEUE_ITEMS);
    if (db.version === 56) {
      db.version = 57;
    }
  }
  // v57/v58 → v58（2026-10-17 排队暂停位落库笔）：新建 send_queue_state（语义见头段 v58）。
  // CREATE IF NOT EXISTS 幂等（铁律②）；零数据回填（空表 = 全 ACTIVE 存量语义）。
  // **判据宽容式含 58**（铁律③）。逐级：只写 58（铁律①）
  if (db.version === 57 || db.version === 58) {
    await db.executeSql(SQL_CREATE_SEND_QUEUE_STATE);
    if (db.version === 57) {
      db.version = 58;
    }
  }
  // v58/v59 → v59（2026-10-19 方案-MCP页施工方案 B2「数据层」）：**双动作**——建 mcp_servers
  // 表 + assistants 补 mcpServers 列（语义与成本如实口径见头段 v59 注释）。**判据宽容式含
  // 59**（铁律③ + v33 起先例：编辑窗口期的中间构建停在 59 且缺表缺列的库，重跑要能进本
  // 分支补建补列—— assistants 行投影含 mcpServers 列的后续构建对缺列库直接抛 SQL 错）。
  // 零数据回填（新表空集 + DEFAULT '' 即「零勾选」均存量语义）。中断重跑幂等（铁律①②）：
  // CREATE IF NOT EXISTS 天然幂等 + ALTER 前 columnExists 守卫。逐级：只写 59（铁律①）
  if (db.version === 58 || db.version === 59) {
    await db.executeSql(SQL_CREATE_MCP_SERVERS);
    if (!(await columnExists(db, 'assistants', 'mcpServers'))) {
      await db.executeSql("ALTER TABLE assistants ADD COLUMN mcpServers TEXT NOT NULL DEFAULT ''");
    }
    if (db.version === 58) {
      db.version = 59;
    }
  }
  // v59/v60 → v60（2026-10-19 方案-MCP二期对标增强 C1）：mcp_servers 加 authKind /
  // protocolVersion 两列（语义见上方 v60 注释与 ChatDbSchema 建表串注释）。ALTER 前逐列
  // columnExists 守卫（铁律②——中断重跑不报 duplicate column）；**零数据回填**（DEFAULT
  // 'custom' / '' 即存量行为等价值：自定义头组 UI + 自动协商）。**判据宽容式含 60**（铁律
  // ③ + v33 起先例：编辑窗口期的中间构建停在 60 且缺列的库，重跑要能进本分支补列）。
  // 逐级：只写 60（铁律①）
  if (db.version === 59 || db.version === 60) {
    if (!(await columnExists(db, 'mcp_servers', 'authKind'))) {
      await db.executeSql(
        "ALTER TABLE mcp_servers ADD COLUMN authKind TEXT NOT NULL DEFAULT 'custom'");
    }
    if (!(await columnExists(db, 'mcp_servers', 'protocolVersion'))) {
      await db.executeSql(
        "ALTER TABLE mcp_servers ADD COLUMN protocolVersion TEXT NOT NULL DEFAULT ''");
    }
    if (db.version === 59) {
      db.version = 60;
    }
  }
  // v60/v61 → v61（2026-10-21 方案-引用功能全链路 U-C）：messages 加 quote_text 一列
  //（用户消息的引用全文快照；NULL = 无引用——列有意无约束，与 parentMessageId/seq 同款
  //「无语义 = NULL」；不用 NOT NULL DEFAULT '' 是因为空串与 NULL 语义分家：NULL = 从未有
  // 引用，'' 不出现）。零数据回填（存量行全 NULL 即存量语义）。中断重跑幂等（铁律①②）：
  // ALTER 后写 61 前中断 → 库仍 v60 → 重跑进分支 → columnExists 跳过 → 写 61；写 61 后
  // 中断 → 重跑因 columnExists 双保险。**判据宽容式含 61**（铁律③ + v33 起先例：编辑
  // 窗口期的中间构建停在 61 且缺列的库，重跑要能进本分支补列）。逐级：只写 61（铁律①）
  if (db.version === 60 || db.version === 61) {
    if (!(await columnExists(db, 'messages', 'quote_text'))) {
      await db.executeSql("ALTER TABLE messages ADD COLUMN quote_text TEXT DEFAULT NULL");
    }
    if (db.version === 60) {
      db.version = 61;
    }
  }
  // v61/v62 → v62（2026-10-25 控制台助手退役与合并笔）：控制台会话改指默认助手 + 删
  // assistant-console 行（双动作语义与幂等论证见头段 v62 注释）。**判据宽容式含 62**
  //（铁律③ + v33 起先例：编辑窗口期的中间构建停在 62 且行未迁的库，重跑要能进本分支
  // 补迁）。逐级：只写 62（铁律①）
  if (db.version === 61 || db.version === 62) {
    await db.executeSql("UPDATE conversations SET assistantId = 'assistant-default' " +
      "WHERE assistantId = 'assistant-console'");
    await db.executeSql("DELETE FROM assistants WHERE id = 'assistant-console'");
    if (db.version === 61) {
      db.version = 62;
    }
  }
  // v62/v63 → v63（2026-10-26 方案-知识库触发精度第一档）：knowledge_entries 加触发精度四列
  //（语义见头段 v63 注释与 ChatDbSchema 建表串注释）。**零数据回填**（DEFAULT 即旧行为等价值）。
  // 中断重跑幂等（铁律①②）：ALTER 后写 63 前中断 → 库仍 v62 → 重跑进分支 → columnExists 跳过
  // → 写 63。**判据宽容式含 63**（铁律③ + v33 起先例：编辑窗口期的中间构建停在 63 且缺列的库，
  // 重跑要能进本分支补列）。逐级：只写 63（铁律①）
  if (db.version === 62 || db.version === 63) {
    if (!(await columnExists(db, 'knowledge_entries', 'matchCase'))) {
      await db.executeSql('ALTER TABLE knowledge_entries ADD COLUMN matchCase INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'knowledge_entries', 'matchWhole'))) {
      await db.executeSql('ALTER TABLE knowledge_entries ADD COLUMN matchWhole INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'knowledge_entries', 'priority'))) {
      await db.executeSql('ALTER TABLE knowledge_entries ADD COLUMN priority INTEGER NOT NULL DEFAULT 100');
    }
    if (!(await columnExists(db, 'knowledge_entries', 'scanDepth'))) {
      await db.executeSql('ALTER TABLE knowledge_entries ADD COLUMN scanDepth INTEGER NOT NULL DEFAULT 8');
    }
    if (db.version === 62) {
      db.version = 63;
    }
  }
  // v63/v64 → v64（2026-11-14 DS 全家桶接入批 S2）：messages 加 server_tools 一列（assistant
  // 行的 DeepSeek 服务端工具原样 JSON 串；NULL = 非官方档轮/无服务端步骤——列义与消费面见
  // 顶段 v64 版本注释）。零数据回填（存量行全 NULL 即存量语义）。中断重跑幂等（铁律①②）：
  // ALTER 后写 64 前中断 → 库仍 v63 → 重跑进分支 → columnExists 跳过 → 写 64；写 64 后
  // 中断 → 重跑因 columnExists 双保险。**判据宽容式含 64**（铁律③ + v33 起先例：编辑窗口期
  // 的中间构建停在 64 且缺列的库，重跑要能进本分支补列）。逐级：只写 64（铁律①）
  if (db.version === 63 || db.version === 64) {
    if (!(await columnExists(db, 'messages', 'server_tools'))) {
      await db.executeSql('ALTER TABLE messages ADD COLUMN server_tools TEXT DEFAULT NULL');
    }
    if (db.version === 63) {
      db.version = 64;
    }
  }
  // v64/v65 → v65（2026-11-14 DS 全家桶二期 S2/#7）：token_usage_events 加 serverToolsUsage
  // 一列（本轮官方服务端工具计次 JSON 串；'' = 无计次）。零数据回填（存量行空串即「无计次」
  // 语义，用量气泡不挂三行）。中断重跑幂等（铁律①②）：ALTER 后写 65 前中断 → 库仍 v64 →
  // 重跑进分支 → columnExists 跳过 → 写 65；写 65 后中断 → 重跑因 columnExists 双保险。
  // **判据宽容式含 65**（铁律③：编辑窗口期的中间构建停在 65 且缺列的库，重跑要能补列）；
  // 逐级：只写 65（铁律①）
  if (db.version === 64 || db.version === 65) {
    if (!(await columnExists(db, 'token_usage_events', 'serverToolsUsage'))) {
      await db.executeSql(
        'ALTER TABLE token_usage_events ADD COLUMN serverToolsUsage TEXT NOT NULL DEFAULT \'\'');
    }
    if (db.version === 64) {
      db.version = 65;
    }
  }
  // v65/v66 → v66（2026-11-17 整体退役加密会话笔）：conversations.locked 墓碑化，存量 locked=1
  // 一次性清零——原加密会话与普通会话自此完全同权（列表/检索/记忆三面归一）。零 schema 变更
  //（列留在建表串里不删，见 ChatDbSchema 注释）；**UPDATE 带 WHERE 条件、命中零行不报错**——
  // 命中零行即合法终态，重跑幂等（铁律②）。**判据宽容式含 66**（铁律③：编辑窗口期中间构建
  // 停在 66 而清值未跑的库，重跑要能补跑）；逐级：只写 66（铁律①）
  if (db.version === 65 || db.version === 66) {
    await db.executeSql('UPDATE conversations SET locked = 0 WHERE locked = 1');
    if (db.version === 65) {
      db.version = 66;
    }
  }
}
