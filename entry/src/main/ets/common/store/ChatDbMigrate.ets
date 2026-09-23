// Schema 维护域（2026-08-30 自 ChatDb 域级最小拆分——迁移钩子幂等化后 ChatDb 将超 400
// 红线：版本号/新装/迁移收拢本文件，ChatDb.doInit 依次调 ensureSchema → migrateSchema；
// ★ 2026-09-23 起建表 SQL 常量整块外迁 ChatDbSchema.ets——本件剔头 1189 已越 1200 硬线，
// 按技术债务清单建档候选缝先拆再落压缩笔改动，常量单一来源自此在彼件）。表结构 v44：
// conversations + messages（v42 起含 coversToSeq 压缩摘要覆盖边界列，见迁移区 v42 注释）
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
// 「内置两张恒列头部」硬钉，改由本列承载列表序，存量回填见迁移区 v40 注释）；v34 起会话消息后推荐
// suggestions 列 + 助手开场推荐 openers 列（语义与解析单落点见迁移区 v34 注释）+
// v38 起助手知识库启用清单 knowledge 列〔'' = 空集合 = 不启用任何知识库，与 skills 列
// 同义、与 tools 列反义〕）+ skills / skill_files（v30 新建——技能层两表：skills = 技能本体
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
// 参考值，非 0 = 用户覆盖——见迁移区 v33 注释，本笔无消费面）+
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
// ★ 不进导出清单——本地后悔药不是跨设备资产；删助手同事务级联删其助手库快照）。
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
  SQL_CREATE_CONVERSATIONS, SQL_CREATE_KNOWLEDGE_BOOKS, SQL_CREATE_KNOWLEDGE_ENTRIES,
  SQL_CREATE_KNOWLEDGE_ENTRIES_BOOK_INDEX, SQL_CREATE_KNOWLEDGE_FILES, SQL_CREATE_MEMORIES,
  SQL_CREATE_MEMORIES_TIME_INDEX,
  SQL_CREATE_MEMORY_SNAPSHOTS, SQL_CREATE_MEMORY_SNAPSHOTS_INDEX, SQL_CREATE_MESSAGE_ATTACHMENTS,
  SQL_CREATE_MESSAGE_ATTACHMENTS_CONV_INDEX, SQL_CREATE_MESSAGE_ATTACHMENTS_MSG_INDEX,
  SQL_CREATE_MESSAGES, SQL_CREATE_MESSAGES_INDEX, SQL_CREATE_MESSAGES_SEQ_INDEX,
  SQL_CREATE_PRICE_TEMPLATES, SQL_CREATE_PROMPT_TEMPLATES, SQL_CREATE_PROVIDER_KEYS,
  SQL_CREATE_PROVIDER_KEYS_INDEX, SQL_CREATE_PROVIDER_MODELS, SQL_CREATE_PROVIDER_MODELS_INDEX,
  SQL_CREATE_PROVIDERS, SQL_CREATE_SKILLS, SQL_CREATE_SKILL_FILES, SQL_CREATE_TOKEN_USAGE_CONV_INDEX,
  SQL_CREATE_TOKEN_USAGE_EVENTS, SQL_CREATE_TOKEN_USAGE_TIME_INDEX
} from './ChatDbSchema';

// export（2026-09-12 为自检域 A1「store.version 与本常量一致」加出口；自检域 2026-09-20
// 全量退役后仍导出——各断言脚本按「export const DB_VERSION」形态钉住本行共五处，收回
// export 需同笔改钉，故留出口当只读单一来源）
export const DB_VERSION: number = 44;

// v34（2026-09-19 推荐问题，任务书-推荐问题-20260919 执行）：两列——①conversations 补
// suggestions（消息后追问推荐 JSON 数组串，'' = 无；会话级末条覆盖写，显示面只有末条
// 助手消息，消息级持久化是冗余写——RikkaHub 同构；发送即清空写 ''，退出重进回放显示
// **不重新生成**）；②assistants 补 openers（新会话开场推荐问题 JSON 数组串）。解析/序列化
// 单一落点 = common/SuggestGen.ets parseSuggestions/serializeSuggestions（两列共用一套，
// 本域只存取原串）。**无数据回填**（存量行 '' 即「无推荐」语义）；不加索引（会话行是
// 用户对话数据自然有界，按 id 点查）
// ★ 2026-09-19 当晚决明拍板：**开场推荐链退役**（新会话开场推荐不做，只留消息后追问
// 推荐）——openers 列保留为死列（只加不改红线，全仓零读写零消费；AssistantRow 字段与
// 查询投影已随退役删除，列不删）。suggestions 列为活跃列照常
// ★ ExportImport 零改动：导出 SELECT * 全量透传自动携带；导入「备份行缺的新列落表默认值」
// 语义（485 行注释）→ 旧备份恢复后两列落 ''，零迁移零报错

// v35（2026-09-20 助手级记忆，任务书-助手级记忆-20260920 执行）：两动作——①新建
// assistant_memories 表（助手级记忆库：assistant_id = 归属助手（归属语义，非 memories 表
// 的「来源标注」语义——两库语义刻意分离不混注，见 MemoryDb.ets 头注释）；行 id 前缀
// 'asmem-'（连字符形态，全局 'mem-' 同形，均出自 nextMessageId，仅供人读——跨库拦截靠
// 执行器各自的定位集/查询集锁本库，非前缀判据）；②assistants 补 memoryScope
// 列（'global' 默认 = 全局记忆 = 存量行为原样；'assistant' = 助手记忆——注入/沉淀/检索
// 全走自己的库，二选一切换不混注）。**无数据回填**（DEFAULT 'global' 即存量语义，升级后
// 全部助手零行为变化）；索引一枚 = 按 assistant_id 归属查询（列表/注入/级联删主路径；
// 全表 ≤ MEMORY_MAX_TOTAL 200 行，不设 time 索引）。CRUD 在 MemoryDb.ets（与全局 memories
// 同文件同构）
// ★ ExportImport：EXPORT_TABLES +assistant_memories 随备份走；旧备份缺本表 = 缺失容忍
//（导入按表存在性跳过），恢复后助手库为空零报错
// ★ 中断重跑幂等（铁律①②）：CREATE IF NOT EXISTS + ALTER 前 columnExists 守卫

// v36（2026-09-20 消息重新生成·多版本保留）：messages 补两列——variants（同槽位多版本
// JSON 数组串，'' = 从未重试过的单版消息；结构/解析/序列化单源 = MessageVariantDb.ets
// parseMessageVariants/serializeMessageVariants（★ 2026-09-20 注释核正：两个纯函数随
// 七百九十三笔迁往 MessageVariantDb 后本件不再导出，消费方照常从新件 import），每版
// {content, reasoning, tokens, completion, durationMs, cached}）+ variant_active（选中版
// 下标，与 content 列恒同步——**content 列恒存选中版内容 = 现役全部读方（回放/搜索/统计/
// get_chats/导出）零改动**的投影设计）。写点三处：重试开始保底写（ChatSendCtrl.retryLast，
// 旧答案入 variants[0] 防覆盖丢失）/ 重试收尾追加写（finishStream 与工具轮中间收尾
// settleRoundAssistant——单行 UPDATE content+reasoning+variants+variant_active 四列同条）/
// 切换键换版写（ChatRetryCtrl.switchVariant〔★ 2026-09-20 注释核正：旧注记成页面侧同名
// 方法，该件全仓无此定义、只有 onVariantSwitch 上行〕，content 投影随 active 同步换）。
// **无数据回填**（'' + 0 即
// 「单版、无多版本」存量语义）；不加索引（切换/重试均按 id 点查主键直达）
// ★ ExportImport 零改动：导出 SELECT * 自动携带；导入按目标列交集——旧备份行缺两键落
// 表默认值（''/0 = 单版语义，v34 suggestions 同款先例）
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过

// v37（2026-09-21 消息存储机制改造笔 1，任务书-消息存储机制改造笔1-20260921 执行）：
// messages 补 seq 列（会话内 0 起显式序号——把消息排序从 createdAt 依赖里迁出来的第一步，
// 笔 3 切读取后生效）+ 索引 idx_messages_conv_seq(conversationId, seq)（笔 3 的读取切换
// 与回填判定都走它）。★ **列有意无任何约束**（`INTEGER DEFAULT NULL`，不设 NOT NULL /
// UNIQUE / CHECK）：笔 1 不动写入路径（当时新行一律落默认 NULL），**笔 2 起全部产品写入点
// 必铸本列**（分配器 `MessageSeqDb.nextRowSeq`，七处逐点钉在 assert-store-consistency 144 组）
// ——仍允许 NULL 的只剩三类：v37 之前的存量行、旧备份导回行、域外调用点漏铸的兜底行，一律由
// 启动补号 sweep 归一（导出侧 NULL→0 归一使候选门须连「重号」一并识别，见下方 ★ 段）。任何约束
// 都会让上述三类行与「重试清扫天然产的空洞」插入失败 = 聊天全断；约束是否升级留笔 3 评估
//（重试清扫天然产空洞，UNIQUE 大概率永不设）。**凡读本列的新代码必须容忍 NULL**
// ★ **本分支不回填**（回填 = 启动 sweep 单一代码路径 `ChatDb.backfillMessageSeq`，首启时
// 迁移完成后自然全量执行；本分支只做 schema）
// ★ 回填规则（唯一权威，实现见 ChatDb.computeSeqBackfill）：每会话按
// `createdAt ASC, rowid ASC` 重排赋 0,1,2,…；只写 seq 列，禁改任何既有列
// ★ ExportImport 零改动（导出 SELECT * 自动携带本列；导入按目标列交集）——但**导出侧的
// NULL 归一（NULL → 0，readTableRows 列型分派）会把「未编号」写成真 0**，故 sweep 的候选
// 判据不能只看 NULL，须连「重号」一并识别（证据链与后果见 ChatDb.backfillMessageSeq 注释）
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过

// v38（2026-09-21 世界书知识库首版，任务书-世界书知识库-20260921 执行；用户可见名
// 「知识库」）：三动作——①新建 knowledge_books 表（知识库本体：一行一本，name 书名 +
// sortOrder 卡序；上限 KNOWLEDGE_BOOK_MAX 20 在页面层拦，本表不设约束）；②新建
// knowledge_entries 表（条目：一行一条，title 名称 + keywords 关键词 + content 正文三字段，
// bookId 归属书；检索主路径 = 按 bookId 取行，故加索引一枚，与 assistant_memories 同款
// 归属索引；条目上限 KNOWLEDGE_ENTRY_MAX 100 在页面层拦）+ 索引
// idx_knowledge_entries_book；③assistants 补 knowledge 列（助手启用的知识库 id 清单 JSON
// 串——★ 语义与 skills 列同、与 tools 列**相反**：'' = 空集合 = 不启用任何知识库，新装与
// 存量助手升级后零启用零声明，请求逐字节同升级前；解析/序列化单一落点 =
// KnowledgeText.parseEnabledKnowledgeIds / serializeEnabledKnowledgeIds，另立一份而**禁复用**
// 其他列的解析函数——三列语义各不相同，复用即等着被后人按错口径改坏）。
// **无数据回填**（知识库自空起步不预置；知识库条目是用户手写资产，不由模型沉淀）。
// ★ ExportImport：EXPORT_TABLES +knowledge_books/knowledge_entries 随备份走（书在条目之前
// = 依赖序）；旧备份缺两表 = 缺失容忍（导入按表存在性跳过），恢复后知识库为空零报错
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫、CREATE ... IF NOT EXISTS 天然幂等

// v39（2026-09-21 知识库第二笔下本，任务书-知识库写入口与上限放宽-20260921 执行）：一列——
// knowledge_entries 补 source（条目来源标签：'user' = 用户写 / 'assistant' = 助手写；新笔起
// 助手可经 manage_knowledge 写入条目，本列让 UI 与用户能分辨来源）。**无数据回填**：DEFAULT
// 'user' 即存量语义——既有条目全是用户手写，升级后行为与标记零变化（UI 只标非默认行「助手
// 写入」，照技能库只标「内置」行同款）。值域常量与判定散落在 UI/工具两侧读处，单一来源 =
// KnowledgeDb 的行映射（row.source）；**update 不改本列**（来源不随后续编辑翻转）。
// ★ ExportImport 零改动（导出 SELECT * 自动携带本列；导入按目标列交集，旧备份缺该列走表默认
// 值 'user' = 旧备份导回后条目无标记，语义正确）
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过

// v40（2026-09-22 助手自定义列表序）：一列——assistants 补 sortOrder（助手列表自定义序，
// 小者在前、0 起；语义与 providers.sortOrder 同款）。与 v29 给 memories 加列同族，两点不同：
// ①**有数据回填**（不是纯默认值就够）——v40 起读侧撤除「内置两张恒列头部」硬钉（原
// queryAssistants 把内置默认/控制台助手抽出来拼到数组首的实现随本笔删除），列表序改由本列
// 单键承载；若只给 DEFAULT 0 不回填，升级后全表并列 0 会退化成 createdAt 序，而内置两张由
// seed 落行、createdAt 晚于存量自建助手 ⇒ 会沉底 = 可见的顺序回归。回填规则 = 复刻升级前
// 的可见序：内置两张置 0/1，其余保持 createdAt 升序续排 2..N（实现见 backfillAssistantSortOrder）。
// ②**此后内置两张可被用户拖到任意位置**（决明 2026-09-22 拍板，与四家竞品一致：内置项一律
// 不置顶，唯一内置特权是禁删）——本列是列表序的**唯一权威**，UI 不再有任何位置特判。
// ★ 迁移判据 = `db.version === 39 || 首次补列`（回填条件：停在 39 = 迁移未完成；或列刚补上
// = 从未有过用户序）。**停在 40 且列已在位时绝不重排**（那是稳态，列里可能是用户自己拖的序）。
// 中断窗口封堵：ALTER 成功而回填/写版本号前中断 ⇒ 下次仍停在 39 ⇒ 重新回填，而回填是
// createdAt 的确定性重算（同库同结果）⇒ 重跑不产生第二次不同的序；此窗口内应用处于
// 「数据库初始化失败」态，用户无从拖拽，故重算不会抹掉用户意图。
// ★ ExportImport 零改动（导出 SELECT * 自动携带本列；旧备份缺该列走表默认 0 = 导回后
// 全表并列 0，退化为 createdAt 序——可接受，且用户拖一次即恢复自定义序）
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫、CREATE 天然无需（无新表）

// v41（2026-09-22 记忆优化历史，方案-记忆优化历史-20260922 执行）：新建 memory_snapshots
// 表 + 一枚索引——记忆优化由「不可撤销」改「可回退」的后悔药。表结构/语义见上方建表 SQL
// 注释，行读写在 MemoryDb.ets（查询/整库恢复/级联删四函数）。
// **无数据回填**（历史快照本就不存在，表自空起步，升级后首次优化才产生第一份）。
// ★ 不进 EXPORT_TABLES：本地后悔药不是跨设备资产（与 message_attachments / price_templates
//   两表同款「不进导出清单」先例）；ExportImport.ets 零改动。
// ★ 中断重跑幂等（铁律①②）：纯 CREATE IF NOT EXISTS、零 ALTER、无数据回填——天然幂等

// v42（2026-09-23 上下文压缩，任务书-上下文压缩-20260923 执行）：messages 补 coversToSeq
// 一列（压缩摘要行的覆盖边界：role='summary' 行专用，值 = 本条摘要覆盖到的最大 seq〔含〕
// ——请求组装按它裁掉被压段；非摘要行恒 NULL = 无摘要）。摘要行**追加在会话末尾**（seq 由
// 写入侧分配器 MessageSeqDb.nextRowSeq 铸造，不重排任何行的 seq——物理位置在末尾、请求位置
// 在头部，两者解耦正是记本列的用途）；读写在 CompressDb.ets，组装边界裁剪在
// ChatHistoryBuilder.ets。role 列建表无 CHECK 约束 ⇒ 新增 'summary' 取值零迁移负担。
// **无数据回填**（DEFAULT NULL 即「无摘要」存量语义）；不加索引（每会话至多一条生效摘要，
// 按 seq DESC 取第一条全表扫代价可忽略）。★ ExportImport 零改动：messages 已在导出清单，
// SELECT * 自动携带新列；老备份无该列 → 导入落 NULL = 无摘要，安全。
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过

// v44（2026-09-23 首字耗时笔）：token_usage_events 补 firstTokenMs 一列（整轮首字耗时毫秒
// = 本轮首个**正文或思考**增量到达时刻 − 流起点；跨流取**首个非 0**——用户第一次看到字的
// 那一刻即定格，口径见 ChatUsageRoundCtrl 域头注释与 AiTypes.AiStreamHandlers 第四参）。
// ★ 与请求日志的「首字节」（首个数据块，含空保活帧；只在日志开关打开时测、只存内存环形缓冲）
// 是两个指标，别混：本列是体感口径、常开、落账本，气泡用量弹层与**会话统计面板**（Token 用量卡
// 「平均首字耗时」行）消费——该行由会话级聚合 sessionUsageTotals 的 fs/fn 两值产出（同日两度
// 改判：原设置页总览第七格与其时段聚合、以及中途试落过的上下文用量面板一行，均已撤除）。
// **无数据回填**（首字只有产生它的那条流知道，存量行恒 0 = 「无该指标」，面板均值分母走
// 非 0 计数，老行天然不进）；不加索引（既有 time/conv 两索引已覆盖聚合面，本列只随行取）。
// ★ ExportImport 零改动：账本表已在导出清单，SELECT * 自动携带新列；老备份无该列 → 导入
// 落表默认值 0，安全。
// ★ 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过

// ★ 版本号 31 的占用史（2026-09-16 单条消息指定技能笔退役留痕——**下一级迁移的作者先读这条**）：
// v31 曾被「会话级技能启用」的 647/648 开发包占用（给会话表加过一列，随该功能退役一并撤除，
// 列定义与本级共用的语义详见本笔变更记录）。装过那两个开发包的设备，库里 version 停在 31、
// 且多一列**死列**（本版全仓零读写，无害）。
// ★ 已处置（2026-09-17 取钥方式笔 v31 号跳过）：上一版留下的「分支判据须宽容 30||31」义务
// 已由 **v32 迁移分支**兑现——分支写 `if (db.version === 30 || db.version === 31)`，停在 31
// 的开发包设备随本次升级一并补列并升到 32（A1 版本不一致的预期态同时消解）；**v32 起号池
// 恢复单调**，31 号永久退役不再复用（改号会重开「停 31 设备漏迁」口子）。新装走
// ensureSchema 建全列直标 DB_VERSION，不经任何迁移分支

// v33（2026-09-17 模型上下文窗口配置，任务书-模型上下文窗口-20260917 执行）：provider_models
// 补 context_window（模型上下文窗口 token 数；0 = 未配置 = **跟随内置参考值**，非 0 = 用户
// 覆盖值）。参考值不落库——由 ModelRegistry.lookupContextBaseline 读时按模型名派生（与能力
// A1 链 caps_user_modified 同构的派生/覆盖范式，见 ModelRegistry 头注释）。**无数据回填**
//（DEFAULT 0 即存量语义 = 全部未配置）；不加索引（模型行是用户手建小数据集）。
// ★ 本列本笔**无任何消费面**——只落「配置 + 存储 + 参考值展示」，历史裁剪/上下文用量/请求
// 组装/费用估计均不读它（决明拍板「用量下次做」）

// v28（2026-09-11 价格模板，任务书-价格模板-20260911 执行）：新建 price_templates 表
//（服务商级价格模板库：providerId 归属 + name 名称 + priceConfig = serializePriceConfig
// 产出的价格 JSON 串原文——结构与解析单源 CostStatsCalc，本表透传不解析；每服务商 ≤20
// 套上限在 PriceTemplateDb 常量；随服务商删除事务级联清理；不随「配置迁移」与「全量
// 导出/导入」走——决明拍板③④，见上方表清单行）。纯 CREATE TABLE IF NOT EXISTS、
// 零 ALTER、无数据回填、无索引（每服务商 ≤20 行按 providerId 全表扫代价可忽略——有意
// 之为防后人当疏漏补索引）。**幂等**：CREATE IF NOT EXISTS 天然幂等，中断重跑安全

// v27（2026-09-10 费用估计，方案-费用估计-20260910 执行）：两列——①token_usage_events 补
// purpose（用途码：'chat' 聊天发送〔存量行唯一来源，DEFAULT 'chat' 回填语义正确〕/ 'title'
// 标题生成 / 'memory' 记忆整理 / 'test' 测试连接 anthropic 探针；费用页按用途分组消费，
// 用量统计页三聚合〔overview/byModel/byDay〕加 purpose='chat' 守卫口径不变）；②
// provider_models 补 price_config（价格 JSON 串，'' = 未配置；结构与解析单一来源 =
// common/store/CostStatsCalc.ets，单位 = 元/百万 tokens）。**无数据回填**

// v26（2026-09-10 缓存命中输入用量显示，方案-缓存命中输入用量显示-20260910 执行）：
// token_usage_events 补 cachedTokens（一行 = 一次发送整轮的缓存命中读 token，跨流求和
// 口径与 prompt/completion 同——promptTokens 语义已含命中部分，cached 只作显示标注与
// 账本留痕）。历史行 DEFAULT 0 = 回放不显示缓存段（表自 v18 起步、缓存自 v26 起记，
// 符合预期）。消费面 = 消息 meta 行括号内缀（ChatPageLoad 回填 + ChatMessageItem 渲染）；
// 设置页统计聚合（usageOverview/usageByModel/usageByDay）不消费本列——缓存聚合/命中率
// 卡为统计页域独立立项（方案档 §四不做边界）。**无数据回填**

// v25（2026-09-10 搜索结果条数助手级可调，方案-搜索条数助手级可调-20260910 执行）：assistants
// 补 searchResultCount（助手级单次搜索返回条数上限：1~25，默认 5 = 旧全局常量
// SEARCH_RESULT_COUNT 同值——存量助手与新建助手行为逐字节零回归）。值域常量与「存储值 →
// 生效条数」换算单一来源 = common/search/SearchLimits.resolveSearchResultCount；UI = 助手
// 「工具调用」页上限滑轨卡之后同形制的一张滑轨卡。**无数据回填**（DEFAULT 5 即旧行为）
// ★ 归属助手级而非全局偏好键的理由（不制造「开关在助手级、参数在全局」的分裂）与值到达
// 执行器的中转键机制 = SearchLimits.ets 头注释

// v24（2026-09-10 会话级覆盖层，方案-会话级覆盖层模型与联网-20260910 执行）：conversations
// 补会话级覆盖三列——modelProviderId + modelId（会话级模型覆盖，'' = 未覆盖；消费 = 发送链
// 解析 ①级，替换原「active 两键」）+ webSearchOverride（会话级联网开关覆盖，'' = 跟随助手
// 配置 / '0' = 本会话关闭；助手未启用联网时为硬闸不可覆盖）。三列语义与读写函数见 ChatDb
// 同节注释；**无数据回填**（旧 active 两键的存量值不迁移——迁移它等于把"全局最近选择"
// 固化成某会话的覆盖，与「会话级」语义相悖）

// v23（2026-09-09 附件全量落盘第一轮·数据域，任务书-附件落盘-20260909）：新建
// message_attachments 附件元数据表 + 两索引（msg = 消息级联删 / conv = 按会话查）。生命周期
// = 选附件即直写 filesDir/attachments（隐私会话例外走 cacheDir 临时区、全程零落库）；发送
// 成功随消息落行（文件零迁移——Cube/RikkaHub 取证同款「pick 即直写常驻目录」形态）；删会话
// /删助手同事务级联删行、commit 后删文件；启动 reconcileAttachments 库盘收敛（孤儿行删行 +
// 孤儿文件删文件；「行在文件不在」保留行——决明拍板，元数据不轻易丢弃，第三轮预览显「文件
// 已不在本机」）。导出不带附件元数据（EXPORT_TABLES 不动——与文件本体同进同出，存储管理笔
// 再拍）。零 UI 变化（历史消息仍只显示 [附件] 文件名 标注）

// v22（2026-09-09 工具调用轮数上限可设置，ZCode 侧）：assistants 补 toolStepLimit
//（助手级工具调用轮数上限：0 = 不限制〔应用层不设助手级上限，由 ToolLimits.TOOL_STEP_HARD_CAP
// 256 兜底防死循环扣费〕/ 1~32 = 该助手单次发送内工具调用轮数上限；默认 32 = 旧全局常量
// MAX_TOOL_STEPS 同值，存量助手与新建助手零行为变化）。值域常量与「存储值 → 生效上限」
// 换算单一来源 = ToolLimits.resolveToolStepLimit；UI = 助手「工具调用」页首卡滑轨。无数据回填

// v21（2026-09-08 模型选择半模态优化，任务书-模型选择半模态优化-20260908 执行）：
// provider_models 补 favorite（模型收藏标记，0 = 未收藏 = 存量行为不变；1 = 收藏——选择
// 面板行内爱心 + 「全部/收藏」分段过滤）。随模型行同生命周期：删模型 / 删服务商 /「获取
// 模型」取消勾选即随行清除，重新获取后需重新收藏。本机语义——ProviderShare 单家分享不
// 携带（ExportImport 零改动：导出 SELECT * 透传、导入按列名过滤缺列走表默认值）

// v20（2026-09-08 记忆域，任务书-记忆域-20260908 执行）：①新建 memories 表（跨会话
// 长期记忆：一行一条稳定事实；source 'auto' 退出会话自动整理 / 'manual' 记忆页手动添加；
// assistantId = 沉淀来源助手仅展示用、conversationId = 来源会话仅追溯用——删会话不级联
// 删记忆〔跨会话资产〕、删助手置空 assistantId 不删行〔AssistantDb 级联〕；索引
// updatedAt = 列表倒序；有界红线 = 单条 ≤500 字 + 库内 ≤200 条 + 注入 ≤30 条/2000 字
// 〔上限执行在 MemoryText/MemoryDb/MemoryGen〕；CRUD 在 MemoryDb.ets）+ ②assistants 补
// memoryInject / memorySink 两列（助手级记忆开关：注入 = 会话发送时注入记忆块、沉淀 =
// 退出会话时整理沉淀；默认 1 开——与全局总开关开 + 自动整理关默认组合叠加 = 新装零请求
// 零注入零回归）。ExportImport EXPORT_TABLES +memories 随备份走

// v19（2026-09-08 会话搜索与收藏，任务书-会话搜索与收藏-20260907 执行）：conversations 补
// favorite（会话收藏标记，0 = 未收藏 = 存量行为不变；1 = 收藏——列表卡片星标 + 卡片菜单
// 「收藏/取消收藏」+ 列表顶部「全部/收藏」分段过滤）。收藏不改时间排序（updatedAt 零新写点，
// setConversationLocked 同口径）。标记仅本机语义——ExportImport 零改动：导出 SELECT * 透传、
// 导入列过滤仅取目标表存在列且行缺该列走表默认值（旧版备份导入自动为未收藏）

// v18（2026-09-06 token 用量统计）：新建 token_usage_events 账本表（一行 = 一次用户发送
// 整轮聚合——含工具轮 N 流与 Key 失败切换的跨流求和，口径见 UsageStatsDb.ets 头注释；
// 只追加不更新，删会话级联删）。存量消息不统计不回填（决明拍板口径⑥）——表从空起步，
// 升级后新对话才产生行

// v17（2026-09-05 AI 会话标题自动生成）：conversations 补 titleSource（标题来源三态：
// '' = 占位〔新建行与存量「新对话」行——首条消息升级为截断占位标题、AI 回复完成后
// 触发生成〕/ 'ai' = AI 已生成〔成功即止，不再自动生成〕/ 'manual' = 用户手改〔改名
// 与写回竞态的用户侧终胜出标记，AI 生成链两道守卫〔触发前 + 写回前重查〕均见 manual
// 即放弃——RikkaHub 无来源列被 force 覆盖用户改名是反面教材〕）。写回/占位/改名
// 三写点均不动 updatedAt（标题不改变列表时间序）；生成链细节 = common/TitleGen.ets 头注释

// v16（2026-09-04 加密会话）：conversations 加 locked（会话加密标记，0 = 未加密 = 存量
// 行为不变；1 = 加密——列表卡片显示锁标 + 点击进入需通过官方生物识别；只改进入门禁，
// 消息产生/读写/存储链路零改动。开/关锁动作本身均需先通过生物识别——门禁的钥匙不能
// 留在门上）。注意：该标记仅本机生效语义——不参与导出/加密内容本身（消息明文仍在库），
// 防「随手翻看」非防拆库

// v6（2026-08-30 提示词注入）：conversations 加 promptId（会话引用的提示词模板 id，空串 =
// 未选 → 注入回退系统提示词行；引用跟随语义——模板修改后所有引用会话自动
// 用新版）+ 新建 prompt_templates 表（提示词库：系统提示词 = isGlobal=1 唯一行，固定 id
// prompt-global，启动兜底 ensurePromptGlobal 幂等——2026-08-31 起内置默认可重置/库页不显示
// （查询层过滤）；CRUD 在 PromptTemplateDb.ets；无 schema 变化由此行承载，不分表）
// v7（2026-08-30 提示词注入配置）：prompt_templates 补注入配置三列——injectRole（注入
// 身份：'system' 系统身份 = 现状链路 / 'user' 用户身份 / 'assistant' AI 回复身份）、
// injectPosition（'head' 系统提示位 / 'depth' 在用户消息深度 N）、injectDepth（0~4，
// 仅 position='depth' 生效）；三者默认值 system+head+0 = 存量模板注入行为不变零回归
// v8（2026-08-31 余额自定义请求头）：providers 补 balance_headers（余额查询自定义头
// JSON 串，元素 [{k,v}]，序列化语义同聊天 headers 列——AiTypes.serializeHeaderPairs，
// 空 k/v 行丢弃、空数组 = ''；查询发送时逐条追加且允许覆盖默认 Authorization/Accept 头，
// BalanceApi）
// v9（2026-09-01 助手域）：conversations 补 assistantId（会话引用的助手 id，空串 = 未选 →
// 注入链维持「会话提示词 > 系统提示词」既有回退；非空 = 助手提示词优先，引用弱链——
// 助手删除后解析回退既有链，不级联清引用）+ 新建 assistants 表（助手清单：一行一个助手；
// ★字段极简 = 只收 aicontrol 已支持能力——名称/提示词（支持 {{date}} 等变量，发送前
// 应用层替换）；RikkaHub 助手的采样参数/记忆/工具/正则等 aicontrol 暂不支持的能力不建
// 列、不显示，清单录 docs/调研与待办-助手与提示词变量.md；CRUD 在 AssistantDb.ets）
// v10（2026-09-01 助手模型绑定）：assistants 补三列——providerId/modelId（助手级模型绑定，
// 空 = 未绑定；RikkaHub chatModelId 同语义，UI = 助手编辑页「模型设置」卡）；thinkLevel
//（思考档位 '' /off/low/high/max，AiTypes.THINKING_OPTIONS 同枚举；映射机制同会话页 =
// 「关闭」项按绑定服务商 baseUrl supportsThinkingOff 显隐）。删服务商/删模型由 ProviderDb
// 删除函数级联清绑定列（清删机制）；发送链覆盖（解析连接助手级优先）后置未做——登记
// docs/调研与待办-助手与提示词变量.md 待办 2
// v11（2026-09-01 助手高级设定）：assistants 补 advancedParams（助手级采样与上下文参数
// JSON 串，元素键 = temperature/topP/presencePenalty/frequencyPenalty〔仅开关开启才存〕
// + contextCount/maxOutput〔进过上下文页保存即存〕；'' = 未配置 = 全部不发送，存量助手
// 请求体逐字节零回归；解析/序列化在 AiTypes.parse/serializeAssistantAdvancedParams，
// 范式同 providers.headers）。发送链（ChatPromptState 读 → RequestCompose 四协议方言
// 落点 + RequestInject.clipHistoryTail 截取）；删服务商/删模型**不清**本列（采样参数跨
// 模型通用，与 thinkLevel「离开原服务商无意义」语义不同）

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
  db.version = DB_VERSION;
}

// 列存在性检查（幂等守卫——ALTER 前查，铁律②）。PRAGMA table_info 为查询型 PRAGMA，
// 走 querySql（execute/executeSync 官方注明不支持 query，d.ts:7369；查询型 PRAGMA 用
// querySql 系社区多源实践，底层即 SQLite）；ResultSet 用完 close（红线）。表/列名均
// 代码内常量，无注入面
async function columnExists(db: relationalStore.RdbStore, table: string,
  column: string): Promise<boolean> {
  const result: relationalStore.ResultSet = await db.querySql('PRAGMA table_info(' + table + ')');
  try {
    while (result.goToNextRow()) {
      if (result.getString(result.getColumnIndex('name')) === column) {
        return true;
      }
    }
    return false;
  } finally {
    result.close();
  }
}

// 逐级迁移（只加不改；每级完成只升本级 version——中断后重跑从当前 version 续传，铁律①）：
// v1 → v2（2026-08-30 服务商管理域）——providers 补 enabled/sortOrder + 建 provider_models
// 表与索引；v1 的 providers 表从未接线（建表不落行），无数据迁移。
// v2 → v3（2026-08-30 详情页改版）——provider_models 补 enabled（存量行默认 1 = 全启用，
// 行为不变）+ providers 补余额八列（默认关/空——存量用户无感，高级页签再配）；列定义与
// 新装建表 SQL 逐列一致；无数据回填
export async function migrateSchema(db: relationalStore.RdbStore): Promise<void> {
  if (db.version === 1) {
    if (!(await columnExists(db, 'providers', 'enabled'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1');
    }
    if (!(await columnExists(db, 'providers', 'sortOrder'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0');
    }
    await db.executeSql(SQL_CREATE_PROVIDER_MODELS);
    await db.executeSql(SQL_CREATE_PROVIDER_MODELS_INDEX);
    db.version = 2;
  }
  if (db.version === 2) {
    if (!(await columnExists(db, 'provider_models', 'enabled'))) {
      await db.executeSql('ALTER TABLE provider_models ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1');
    }
    if (!(await columnExists(db, 'providers', 'balance_enabled'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_enabled INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'providers', 'balance_base_url'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_base_url TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'providers', 'balance_path'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_path TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'providers', 'balance_result_path'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_result_path TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'providers', 'balance_currency'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_currency TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'providers', 'balance_currency_path'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_currency_path TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'providers', 'balance_key'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_key TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'providers', 'balance_last_text'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_last_text TEXT NOT NULL DEFAULT \'\'');
    }
    db.version = 3;
  }
  // v3 → v4（2026-08-30 多 Key 池 + 三协议）——providers 补 protocol（默认 openai =
  // 存量服务商行为不变）+ headers（默认空 = 无自定义头）+ 建 provider_keys 表与索引；
  // 旧单 key 资产 → 池首条目的搬运在 Asset 层（ProviderKeyDb.migrateProviderKeyPools，
  // EntryAbility 启动编排——DB 迁移只管结构，明文不进库）
  if (db.version === 3) {
    if (!(await columnExists(db, 'providers', 'protocol'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN protocol TEXT NOT NULL DEFAULT \'openai\'');
    }
    if (!(await columnExists(db, 'providers', 'headers'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN headers TEXT NOT NULL DEFAULT \'\'');
    }
    await db.executeSql(SQL_CREATE_PROVIDER_KEYS);
    await db.executeSql(SQL_CREATE_PROVIDER_KEYS_INDEX);
    db.version = 4;
  }
  // v4 → v5（2026-08-30 OpenAI Responses 适配）——providers 补 endpoint（默认 'chat' =
  // 存量服务商行为不变）；列定义与新装建表 SQL 逐列一致；无数据回填
  if (db.version === 4) {
    if (!(await columnExists(db, 'providers', 'endpoint'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN endpoint TEXT NOT NULL DEFAULT \'chat\'');
    }
    db.version = 5;
  }
  // v5 → v6（2026-08-30 提示词注入）——conversations 补 promptId（默认空串 = 未选，回退
  // 系统提示词行；存量会话行为不变）+ 建 prompt_templates 表（系统提示词行由
  // PromptTemplateDb ensurePromptGlobal 启动兜底，迁移只管结构）+ 索引无（模板 = 用户
  // 手建小数据集）
  if (db.version === 5) {
    if (!(await columnExists(db, 'conversations', 'promptId'))) {
      await db.executeSql('ALTER TABLE conversations ADD COLUMN promptId TEXT NOT NULL DEFAULT \'\'');
    }
    await db.executeSql(SQL_CREATE_PROMPT_TEMPLATES);
    db.version = 6;
  }
  // v6 → v7（2026-08-30 提示词注入配置）——prompt_templates 补注入配置三列，默认值 =
  // 现状行为（'system'/'head'/0）存量模板零回归；列定义与新装建表 SQL 逐列一致；无数据回填
  if (db.version === 6) {
    if (!(await columnExists(db, 'prompt_templates', 'injectRole'))) {
      await db.executeSql('ALTER TABLE prompt_templates ADD COLUMN injectRole TEXT NOT NULL DEFAULT \'system\'');
    }
    if (!(await columnExists(db, 'prompt_templates', 'injectPosition'))) {
      await db.executeSql('ALTER TABLE prompt_templates ADD COLUMN injectPosition TEXT NOT NULL DEFAULT \'head\'');
    }
    if (!(await columnExists(db, 'prompt_templates', 'injectDepth'))) {
      await db.executeSql('ALTER TABLE prompt_templates ADD COLUMN injectDepth INTEGER NOT NULL DEFAULT 0');
    }
    db.version = 7;
  }
  // v7 → v8（2026-08-31 余额自定义请求头）——providers 补 balance_headers（默认 '' = 无，
  // 存量查询行为不变）；列定义与新装建表 SQL 逐列一致；无数据回填
  if (db.version === 7) {
    if (!(await columnExists(db, 'providers', 'balance_headers'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN balance_headers TEXT NOT NULL DEFAULT \'\'');
    }
    db.version = 8;
  }
  // v8 → v9（2026-09-01 助手域）——conversations 补 assistantId（默认空串 = 未选，存量
  // 会话注入行为不变）+ 建 assistants 表（助手清单，用户手建小数据集无索引）；列定义与
  // 新装建表 SQL 逐列一致；无数据回填、无 seed（无助手 = 既有注入链，等价 RikkaHub 默认
  // 空提示词助手）
  if (db.version === 8) {
    if (!(await columnExists(db, 'conversations', 'assistantId'))) {
      await db.executeSql('ALTER TABLE conversations ADD COLUMN assistantId TEXT NOT NULL DEFAULT \'\'');
    }
    await db.executeSql(SQL_CREATE_ASSISTANTS);
    db.version = 9;
  }
  // v9 → v10（2026-09-01 助手模型绑定）——assistants 补三列（providerId/modelId 默认空 =
  // 未绑定、thinkLevel 默认 '' = 默认不传；存量助手行为不变）；列定义与新装建表 SQL 逐列
  // 一致；无数据回填
  if (db.version === 9) {
    if (!(await columnExists(db, 'assistants', 'providerId'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN providerId TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'assistants', 'modelId'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN modelId TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'assistants', 'thinkLevel'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN thinkLevel TEXT NOT NULL DEFAULT \'\'');
    }
    db.version = 10;
  }
  // v10 → v11（2026-09-01 助手高级设定）——assistants 补 advancedParams（默认 '' = 未
  // 配置，存量助手请求体零回归）；列定义与新装建表 SQL 逐列一致；无数据回填
  if (db.version === 10) {
    if (!(await columnExists(db, 'assistants', 'advancedParams'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN advancedParams TEXT NOT NULL DEFAULT \'\'');
    }
    db.version = 11;
  }
  // v11 → v12（2026-09-01 Anthropic 提示缓存）——providers 补 prompt_cache_enabled
  // （默认 0 = 关——写入 1.25× 计费，用户显式开启才花钱）+ prompt_cache_ttl（默认 '5m'，
  // 官方两档 '5m'|'1h'；仅 anthropic 协议消费）；列定义与新装建表 SQL 逐列一致；无数据回填
  if (db.version === 11) {
    if (!(await columnExists(db, 'providers', 'prompt_cache_enabled'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN prompt_cache_enabled INTEGER NOT NULL DEFAULT 0');
    }
    if (!(await columnExists(db, 'providers', 'prompt_cache_ttl'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN prompt_cache_ttl TEXT NOT NULL DEFAULT \'5m\'');
    }
    db.version = 12;
  }
  // v12 → v13（2026-09-02 自定义 Body）——providers 补 body_overrides（默认 '' = 无覆盖，
  // 请求体逐字节零回归）；列定义与新装建表 SQL 逐列一致；无数据回填
  if (db.version === 12) {
    if (!(await columnExists(db, 'providers', 'body_overrides'))) {
      await db.executeSql('ALTER TABLE providers ADD COLUMN body_overrides TEXT NOT NULL DEFAULT \'\'');
    }
    db.version = 13;
  }
  // v13 → v14（2026-09-02 工具调用底层）——assistants 补 tools（默认 '' = 默认集合，
  // 存量助手按内置 defaultEnabled 项生效）；列定义与新装建表 SQL 逐列一致；无数据回填
  // ★ 2026-09-02 建表 SQL 漏列补账（升版三处同步漏了第一处——SQL_CREATE_ASSISTANTS 曾缺
  //   tools 列；新装库 ensureSchema 建表后直接标 14 跳过本分支 → 表永缺列 → 助手列表查询
  //   失败/新建报 SQLite Generic error。com.jueming.aicontrol.chat 换包名后全新库即命中）：
  //   version=14 的库一并进本分支做幂等补列（列已存在 = zero-op，不写 version——逐级语义
  //   不变，仅多查一次 PRAGMA）
  if (db.version === 13 || db.version === 14) {
    if (!(await columnExists(db, 'assistants', 'tools'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN tools TEXT NOT NULL DEFAULT \'\'');
    }
    if (db.version === 13) {
      db.version = 14;
    }
  }
  // v14 → v15（2026-09-03 Cube 吸收 A1 模型能力注册表，任务书-Cube兼容画像与模型匹配
  // 引擎吸收-20260903）——provider_models 补 caps_user_modified（能力派生/覆盖标志，
  // 语义见上方 v15 建表注释）。迁移回填规则 = caps 非空行置 1：存量非空 caps 全为用户
  // 手设（事实依据——获取模型入库恒空串 ModelFetchSheet、遗留迁移空串
  // ProviderDb.ensureProvidersMigrated、导入走 ProviderShare 也经 insertModel，非空仅
  // 出自编辑页手勾）= 存量展示与升级前一致零回归。中断重跑幂等：列已存在跳过 ALTER，
  // 回填为确定性计算重跑无差（铁律①②）
  if (db.version === 14) {
    if (!(await columnExists(db, 'provider_models', 'caps_user_modified'))) {
      await db.executeSql('ALTER TABLE provider_models ADD COLUMN caps_user_modified INTEGER NOT NULL DEFAULT 0');
    }
    await db.executeSql('UPDATE provider_models SET caps_user_modified = CASE WHEN caps != \'\' THEN 1 ELSE 0 END');
    db.version = 15;
  }
  // v15 → v16（2026-09-04 加密会话）——conversations 补 locked（默认 0 = 未加密，存量
  // 会话零回归）；列定义与新装建表 SQL 逐列一致；无数据回填（存量全部未加密）
  if (db.version === 15) {
    if (!(await columnExists(db, 'conversations', 'locked'))) {
      await db.executeSql('ALTER TABLE conversations ADD COLUMN locked INTEGER NOT NULL DEFAULT 0');
    }
    db.version = 16;
  }
  // v16 → v17（2026-09-05 AI 会话标题自动生成）——conversations 补 titleSource（三态语义
  // 见上方 v17 注释）。迁移回填启发式：存量 title != '新对话' 的行置 'manual'（改过名的
  // 保守视为用户手改——防升级后 AI 生成覆盖用户起的标题）；title = '新对话' 保持 ''
  //（正是最需要补生成的存量，下次对话完成即触发）。中断重跑幂等（铁律①②）：列已存在
  // 跳过 ALTER；回填为确定性计算重跑无差——重跑窗口内 app 未完整启动过（迁移在
  // initChatDb，完成后才有 UI/发送链），'ai' 值在重跑时不可能已存在
  if (db.version === 16) {
    if (!(await columnExists(db, 'conversations', 'titleSource'))) {
      await db.executeSql('ALTER TABLE conversations ADD COLUMN titleSource TEXT NOT NULL DEFAULT \'\'');
    }
    await db.executeSql('UPDATE conversations SET titleSource = ' +
      'CASE WHEN title != \'新对话\' THEN \'manual\' ELSE \'\' END');
    db.version = 17;
  }
  // v17 → v18（2026-09-06 token 用量统计）——新建 token_usage_events 账本表与两索引
  //（表结构/口径见上方 v18 注释与建表 SQL）。纯新建无列变更，存量数据零触碰、不回填
  //（决明口径⑥存量不统计）；CREATE IF NOT EXISTS 天然幂等，中断重跑安全（铁律②）
  if (db.version === 17) {
    await db.executeSql(SQL_CREATE_TOKEN_USAGE_EVENTS);
    await db.executeSql(SQL_CREATE_TOKEN_USAGE_CONV_INDEX);
    await db.executeSql(SQL_CREATE_TOKEN_USAGE_TIME_INDEX);
    db.version = 18;
  }
  // v18 → v19（2026-09-08 会话搜索与收藏）——conversations 补 favorite（默认 0 = 未收藏，
  // 存量会话零回归）；列定义与新装建表 SQL 逐列一致；无数据回填（存量全部未收藏）。
  // 中断重跑幂等（铁律①②）：ALTER 前查列存在，重跑跳过
  if (db.version === 18) {
    if (!(await columnExists(db, 'conversations', 'favorite'))) {
      await db.executeSql('ALTER TABLE conversations ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
    }
    db.version = 19;
  }
  // v19 → v20（2026-09-08 记忆域）——建 memories 表与 updatedAt 索引 + assistants 补
  // 记忆两开关列（默认 1 = 存量助手升级后默认参与，与全局开关默认组合叠加零行为变化）；
  // 列定义与新装建表 SQL 逐列一致；无数据回填。中断重跑幂等（铁律①②）：ALTER 前查列
  // 存在、CREATE IF NOT EXISTS 天然幂等
  if (db.version === 19) {
    if (!(await columnExists(db, 'assistants', 'memoryInject'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN memoryInject INTEGER NOT NULL DEFAULT 1');
    }
    if (!(await columnExists(db, 'assistants', 'memorySink'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN memorySink INTEGER NOT NULL DEFAULT 1');
    }
    await db.executeSql(SQL_CREATE_MEMORIES);
    await db.executeSql(SQL_CREATE_MEMORIES_TIME_INDEX);
    db.version = 20;
  }
  // v20 → v21（2026-09-08 模型选择半模态优化）——provider_models 补 favorite（默认 0 =
  // 未收藏，存量模型零回归）；列定义与新装建表 SQL 逐列一致；无数据回填（存量全部未收藏）。
  // 中断重跑幂等（铁律①②）：ALTER 前查列存在，重跑跳过
  if (db.version === 20) {
    if (!(await columnExists(db, 'provider_models', 'favorite'))) {
      await db.executeSql('ALTER TABLE provider_models ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
    }
    db.version = 21;
  }
  // v21 → v22（2026-09-09 工具调用轮数上限可设置）——assistants 补 toolStepLimit（默认
  // 32 = 旧全局常量 MAX_TOOL_STEPS 同值，存量助手零行为变化；0 = 不限制语义见上方 v22
  // 版本注释）。列定义与新装建表 SQL 逐列一致；无数据回填。中断重跑幂等（铁律①②）：
  // ALTER 前查列存在，重跑跳过
  if (db.version === 21) {
    if (!(await columnExists(db, 'assistants', 'toolStepLimit'))) {
      await db.executeSql('ALTER TABLE assistants ADD COLUMN toolStepLimit INTEGER NOT NULL DEFAULT 32');
    }
    db.version = 22;
  }
  // v22 → v23（2026-09-09 附件全量落盘第一轮·数据域）——新建 message_attachments 表与两索引
  //（表结构/生命周期见上方 v23 版本注释）。纯新建无列变更、无数据回填（历史消息本就没有
  // 附件元数据）；CREATE IF NOT EXISTS 天然幂等，中断重跑安全（铁律②）
  if (db.version === 22) {
    await db.executeSql(SQL_CREATE_MESSAGE_ATTACHMENTS);
    await db.executeSql(SQL_CREATE_MESSAGE_ATTACHMENTS_MSG_INDEX);
    await db.executeSql(SQL_CREATE_MESSAGE_ATTACHMENTS_CONV_INDEX);
    db.version = 23;
  }
  // v23 → v24（2026-09-10 会话级覆盖层）——conversations 补会话级覆盖三列（模型两列 +
  // 联网开关一列，语义见上方 v24 版本注释与 ChatDb 读/写函数）。三列默认 '' = **未覆盖**
  // → 存量会话升级后全部走「跟随助手/默认」链，静默获得新语义（这正是本笔目的，升级
  // 可见行为变化见方案 §七）。列定义与新装建表 SQL 逐列一致；**无数据回填**（旧①级
  // active 两键的存量值不迁移——迁移它等于把"全局最近选择"固化成某个会话的覆盖，
  // 与「会话级」语义相悖，故不迁）。中断重跑幂等（铁律①②）：ALTER 前查列存在，重跑跳过
  if (db.version === 23) {
    if (!(await columnExists(db, 'conversations', 'modelProviderId'))) {
      await db.executeSql(
        'ALTER TABLE conversations ADD COLUMN modelProviderId TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'conversations', 'modelId'))) {
      await db.executeSql('ALTER TABLE conversations ADD COLUMN modelId TEXT NOT NULL DEFAULT \'\'');
    }
    if (!(await columnExists(db, 'conversations', 'webSearchOverride'))) {
      await db.executeSql(
        'ALTER TABLE conversations ADD COLUMN webSearchOverride TEXT NOT NULL DEFAULT \'\'');
    }
    db.version = 24;
  }
  // v24 → v25（2026-09-10 搜索结果条数助手级可调）——assistants 补 searchResultCount（默认
  // 5 = 旧全局常量 SEARCH_RESULT_COUNT 同值，存量助手零行为变化；值域 1~25 与换算语义见
  // 上方 v25 版本注释）。列定义与新装建表 SQL 逐列一致；**无数据回填**。中断重跑幂等
  //（铁律①②）：ALTER 前查列存在，重跑跳过
  if (db.version === 24) {
    if (!(await columnExists(db, 'assistants', 'searchResultCount'))) {
      await db.executeSql(
        'ALTER TABLE assistants ADD COLUMN searchResultCount INTEGER NOT NULL DEFAULT 5');
    }
    db.version = 25;
  }
  // v25 → v26（2026-09-10 缓存命中输入用量显示）——token_usage_events 补 cachedTokens
  //（历史行 DEFAULT 0 = 回放不显示缓存段，语义见上方 v26 注释）。列定义与新装建表 SQL
  // 逐列一致；**无数据回填**（缓存是否命中只有 provider 知道，存量行无从补）。中断重跑
  // 幂等（铁律①②）：ALTER 前查列存在，重跑跳过
  if (db.version === 25) {
    if (!(await columnExists(db, 'token_usage_events', 'cachedTokens'))) {
      await db.executeSql(
        'ALTER TABLE token_usage_events ADD COLUMN cachedTokens INTEGER NOT NULL DEFAULT 0');
    }
    db.version = 26;
  }
  // v26 → v27（2026-09-10 费用估计）——两表各补一列：token_usage_events 补 purpose
  //（DEFAULT 'chat' = 存量行回填语义正确——表自 v18 起唯一写入点是聊天发送链，见上方 v27
  // 注释）+ provider_models 补 price_config（DEFAULT '' = 未配置）。列定义与新装建表 SQL
  // 逐列一致；**无数据回填**。中断重跑幂等（铁律①②）：ALTER 前查列存在，重跑跳过
  if (db.version === 26) {
    if (!(await columnExists(db, 'token_usage_events', 'purpose'))) {
      await db.executeSql(
        "ALTER TABLE token_usage_events ADD COLUMN purpose TEXT NOT NULL DEFAULT 'chat'");
    }
    if (!(await columnExists(db, 'provider_models', 'price_config'))) {
      await db.executeSql(
        "ALTER TABLE provider_models ADD COLUMN price_config TEXT NOT NULL DEFAULT ''");
    }
    db.version = 27;
  }
  // v27 → v28（2026-09-11 价格模板）——新建 price_templates 表（结构/语义见上方 v28 版本
  // 注释与建表 SQL）。纯新建无列变更、无数据回填（新装用户模板库为空，不预置种子——价格
  // 随时会变，预置即过期数据）；CREATE IF NOT EXISTS 天然幂等，中断重跑安全（铁律②）
  if (db.version === 27) {
    await db.executeSql(SQL_CREATE_PRICE_TEMPLATES);
    db.version = 28;
  }
  // v28 → v29（2026-09-12 记忆自定义注入顺序）——memories 表加 sortOrder 列（卡片自定义
  // 序 = 列表序 + 注入选取序 + 注入块内排列序 + 优化输入序号基准，四路消费同源；存量全 0
  // → 按 createdAt/content 兜底序 = 旧注入块渲染序，存量注入块字符串零漂移）。ALTER 前
  // columnExists 幂等守卫（铁律②）；不加索引——全表 ≤ MEMORY_MAX_TOTAL 200 行无性能面
  if (db.version === 28) {
    if (!(await columnExists(db, 'memories', 'sortOrder'))) {
      await db.executeSql('ALTER TABLE memories ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0');
    }
    db.version = 29;
  }
  // v29 → v30（2026-09-13 技能层）——建 skills / skill_files 两表（结构/语义见上方建表
  // 注释）+ assistants 补 skills（DEFAULT '' = 空集合 = 存量助手升级后默认不启用任何技能
  // → 发送链零注入零声明，请求逐字节同升级前，零回归）。**无数据回填**（技能库自空起步，
  // 不预置内置技能——官方预置是二期 seed 立项）。中断重跑幂等（铁律①②）：ALTER 前查列
  // 存在、CREATE IF NOT EXISTS 天然幂等
  if (db.version === 29) {
    if (!(await columnExists(db, 'assistants', 'skills'))) {
      await db.executeSql("ALTER TABLE assistants ADD COLUMN skills TEXT NOT NULL DEFAULT ''");
    }
    await db.executeSql(SQL_CREATE_SKILLS);
    await db.executeSql(SQL_CREATE_SKILL_FILES);
    db.version = 30;
  }
  // v30/v31 → v32（2026-09-17 取钥方式）——providers 加 key_pick_mode 列（'rotate' 默认 =
  // 存量行为不变：按池内卡片顺序轮换；'random' = 每次发送随机挑起始支）。**判据宽容式含 31**
  //（铁律③ + 上方 31 号占用史：装过 647/648 开发包的设备库版本停在 31 且带死列——只写
  // `=== 30` 会让这批设备整段跳过本迁移 = 漏列；v13/v14 同支先例）。ALTER 前 columnExists
  // 幂等守卫（铁律②）；无数据回填（DEFAULT 'rotate' 即存量语义）；不加索引（服务商行数
  // 是用户手建小数据集，查询恒全表已够）
  if (db.version === 30 || db.version === 31) {
    if (!(await columnExists(db, 'providers', 'key_pick_mode'))) {
      await db.executeSql(
        "ALTER TABLE providers ADD COLUMN key_pick_mode TEXT NOT NULL DEFAULT 'rotate'");
    }
    db.version = 32;
  }
  // v32 → v33（2026-09-17 模型上下文窗口配置）——provider_models 加 context_window 列
  //（0 = 未配置 = 跟随内置参考值 / 非 0 = 用户覆盖；语义见上方 v33 版本注释）。**无数据
  // 回填**（DEFAULT 0 即存量语义）；不加索引（模型行是用户手建小数据集）。中断重跑幂等
  //（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过
  if (db.version === 32) {
    if (!(await columnExists(db, 'provider_models', 'context_window'))) {
      await db.executeSql(
        'ALTER TABLE provider_models ADD COLUMN context_window INTEGER NOT NULL DEFAULT 0');
    }
    db.version = 33;
  }
  // v33 → v34（2026-09-19 推荐问题功能）——conversations 补 suggestions + assistants 补
  // openers（语义见上方 v34 版本注释）。列定义与新装建表 SQL 逐列一致；**无数据回填**。
  // 中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过
  // ★ 2026-09-19 当晚真机事故补账（v14 同款形态重演）：功能笔编辑窗口期产出的一个中间
  //   构建被侧载到真机（该包 DB_VERSION 已 34 但建表 SQL 未含两新列——全新库 ensureSchema
  //   建缺列表后直接标 34），`=== 33` 判据永不进 → 列永缺 → 助手查询与内置助手 seed
  //   （insert 桶含 openers 键）全抛 → 助手页全空 + 新建会话 SQLite 报错闪退，装最终
  //   完整包也复现（version 已 34，分支仍不进）。version=34 的库一并进本分支幂等补列
  //   （列已存在 = zero-op 不写 version，逐级语义不变仅多两次 PRAGMA；v13/v14 与
  //   v30/v31 宽容判据双先例）
  if (db.version === 33 || db.version === 34) {
    if (!(await columnExists(db, 'conversations', 'suggestions'))) {
      await db.executeSql(
        "ALTER TABLE conversations ADD COLUMN suggestions TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'assistants', 'openers'))) {
      await db.executeSql(
        "ALTER TABLE assistants ADD COLUMN openers TEXT NOT NULL DEFAULT ''");
    }
    if (db.version === 33) {
      db.version = 34;
    }
  }
  // v34/v35 → v35（2026-09-20 助手级记忆）——建 assistant_memories 表与归属索引 +
  // assistants 补 memoryScope（'global' 默认 = 存量行为原样，语义见上方 v35 版本注释与
  // 建表 SQL 注释）。**判据宽容式含 34**（铁律③ + v33/v34 与 v30/v31 双先例：v34 迁移
  // 分支对停 34 的库是 zero-op 不写 version，侧载过中间包停在 34 的设备要靠本宽容判据
  // 补迁——只写 `=== 34` 会漏）。列定义与新装建表 SQL 逐列一致；**无数据回填**（DEFAULT
  // 'global' 即存量语义）。中断重跑幂等（铁律①②）：ALTER 前 columnExists 守卫、CREATE
  // IF NOT EXISTS 天然幂等
  if (db.version === 34 || db.version === 35) {
    if (!(await columnExists(db, 'assistants', 'memoryScope'))) {
      await db.executeSql(
        "ALTER TABLE assistants ADD COLUMN memoryScope TEXT NOT NULL DEFAULT 'global'");
    }
    await db.executeSql(SQL_CREATE_ASSISTANT_MEMORIES);
    await db.executeSql(SQL_CREATE_ASSISTANT_MEMORIES_ASSISTANT_INDEX);
    if (db.version === 34) {
      db.version = 35;
    }
  }
  // v35/v36 → v36（2026-09-20 消息重新生成·多版本保留）——messages 补 variants +
  // variant_active 两列（投影设计与写点见上方 v36 版本注释）。**判据宽容式含 35**
  //（铁律③ + v33/v34 与 v34/v35 双先例：v35 迁移分支对停 35 的库是 zero-op 不写 version，
  // 侧载过中间包停在 35 的设备要靠本宽容判据补迁——只写 `=== 35` 会漏）。列定义与新装
  // 建表 SQL 逐列一致；**无数据回填**（DEFAULT ''/0 即存量「单版」语义）。中断重跑幂等
  //（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过
  if (db.version === 35 || db.version === 36) {
    if (!(await columnExists(db, 'messages', 'variants'))) {
      await db.executeSql(
        "ALTER TABLE messages ADD COLUMN variants TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'messages', 'variant_active'))) {
      await db.executeSql(
        'ALTER TABLE messages ADD COLUMN variant_active INTEGER NOT NULL DEFAULT 0');
    }
    if (db.version === 35) {
      db.version = 36;
    }
  }
  // v36/v37 → v37（2026-09-21 消息存储机制改造笔 1）——messages 补 seq 列（列语义/无约束
  // 理由/回填规则见上方 v37 版本注释；本分支只做 schema，**不回填**——回填是启动 sweep
  // 的单一代码路径）+ 建 idx_messages_conv_seq。**判据宽容式含 37**（铁律③ + v33/v34、
  // v34/v35、v35/v36 三先例：功能笔编辑窗口期产出的中间构建被侧载到真机，本工程已两次
  // 实锤〔v14、v34——两处补账注释在上〕；停在 37 且 seq 列缺失的库若只写 `=== 36`，本分支
  // 永不进 → 而启动 sweep 的候选查询引用 seq 列会直接抛 SQL 错 → doInit 返假 → 会话页
  // 「数据库初始化失败，发送功能已禁用」）。列定义与新装建表 SQL 逐列一致。中断重跑幂等
  //（铁律①②）：ALTER 前 columnExists 守卫、CREATE INDEX IF NOT EXISTS 天然幂等
  if (db.version === 36 || db.version === 37) {
    if (!(await columnExists(db, 'messages', 'seq'))) {
      await db.executeSql('ALTER TABLE messages ADD COLUMN seq INTEGER DEFAULT NULL');
    }
    await db.executeSql(SQL_CREATE_MESSAGES_SEQ_INDEX);
    if (db.version === 36) {
      db.version = 37;
    }
  }
  // v37/v38 → v38（2026-09-21 世界书知识库首版）——建 knowledge_books / knowledge_entries
  // 两表与索引 + assistants 补 knowledge 列（'' = 空集合 = 存量助手升级后不启用任何知识库
  // → 发送链零声明零注入，请求逐字节同升级前，零回归；语义见上方 v38 版本注释与建表 SQL
  // 注释）。**判据宽容式含 38**（铁律③ + v33/v34、v34/v35、v35/v36、v36/v37 四先例：功能笔
  // 编辑窗口期产出的中间构建被侧载到真机，本工程已两次实锤〔v14、v34——补账注释在上〕；
  // 停在 38 且 knowledge 列缺失的库若只写 `=== 37`，本分支永不进 → 助手查询投影含 knowledge
  // 列会直接抛 SQL 错）。**无数据回填**（知识库自空起步，不预置任何库与条目）。中断重跑
  // 幂等（铁律①②）：ALTER 前 columnExists 守卫、CREATE ... IF NOT EXISTS 天然幂等
  if (db.version === 37 || db.version === 38) {
    if (!(await columnExists(db, 'assistants', 'knowledge'))) {
      await db.executeSql("ALTER TABLE assistants ADD COLUMN knowledge TEXT NOT NULL DEFAULT ''");
    }
    await db.executeSql(SQL_CREATE_KNOWLEDGE_BOOKS);
    await db.executeSql(SQL_CREATE_KNOWLEDGE_ENTRIES);
    await db.executeSql(SQL_CREATE_KNOWLEDGE_ENTRIES_BOOK_INDEX);
    if (db.version === 37) {
      db.version = 38;
    }
  }
  // v38/v39 → v39（2026-09-21 知识库第二笔下本）——knowledge_entries 补 source 列（条目来源
  // 标签 'user' / 'assistant'；DEFAULT 'user' = 存量条目全是用户手写，升级后零变化，语义见上方
  // v39 版本注释与建表 SQL 注释）。**判据宽容式含 39**（铁律③ + v33/v34、v34/v35、v35/v36、
  // v36/v37、v37/v38 五先例：功能笔编辑窗口期产出的中间构建被侧载到真机，本工程已两次实锤
  // 〔v14、v34——补账注释在上〕；停在 39 且 source 列缺失的库若只写 `=== 38`，本分支永不进
  // → 行映射读 source 列会直接抛 SQL 错）。**无数据回填**（DEFAULT 即正确值）。中断重跑幂等
  //（铁律①②）：ALTER 前 columnExists 守卫
  if (db.version === 38 || db.version === 39) {
    if (!(await columnExists(db, 'knowledge_entries', 'source'))) {
      await db.executeSql(
        "ALTER TABLE knowledge_entries ADD COLUMN source TEXT NOT NULL DEFAULT 'user'");
    }
    if (db.version === 38) {
      db.version = 39;
    }
  }
  // v39 → v40（2026-09-22 助手自定义列表序）——assistants 补 sortOrder（列表序单键权威，
  // 语义与回填规则/中断窗口封堵见上方 v40 版本注释）。**有数据回填**（唯一一处非默认值即够
  // 的加列）：条件 = 停在 39（迁移未完成）或**本分支刚补上列**（首次，从未有过用户序）；
  // 停在 40 且列已在位 = 稳态，绝不动（列里可能是用户自己拖的序）。中断重跑幂等（铁律①②）：
  // ALTER 前 columnExists 守卫；回填是 createdAt 的确定性重算，重跑得同一结果
  if (db.version === 39 || db.version === 40) {
    const added: boolean = !(await columnExists(db, 'assistants', 'sortOrder'));
    if (added) {
      await db.executeSql(
        'ALTER TABLE assistants ADD COLUMN sortOrder INTEGER NOT NULL DEFAULT 0');
    }
    if (db.version === 39 || added) {
      await backfillAssistantSortOrder(db);
    }
    if (db.version === 39) {
      db.version = 40;
    }
  }
  // v40/v41 → v41（2026-09-22 记忆优化历史）——建 memory_snapshots 表与索引（表结构/语义
  // 见上方 v41 版本注释与建表 SQL 注释）。**判据宽容式含 41**（铁律③ + v33/v34、v34/v35、
  // v35/v36、v36/v37、v37/v38、v38/v39 六先例：功能笔编辑窗口期产出的中间构建被侧载到
  // 真机，本工程已两次实锤〔v14、v34——补账注释在上〕；停在 41 且本表缺失的库若只写
  // `=== 40`，本分支永不进 → 记忆历史页查询 memory_snapshots 直接抛 SQL 错）。
  // **无数据回填**（表自空起步，不预置任何快照）。中断重跑幂等（铁律①②）：
  // CREATE ... IF NOT EXISTS 天然幂等
  if (db.version === 40 || db.version === 41) {
    await db.executeSql(SQL_CREATE_MEMORY_SNAPSHOTS);
    await db.executeSql(SQL_CREATE_MEMORY_SNAPSHOTS_INDEX);
    if (db.version === 40) {
      db.version = 41;
    }
  }
  // v41/v42 → v42（2026-09-23 上下文压缩）——messages 补 coversToSeq（列语义/无约束理由/
  // 组装消费面见上方 v42 版本注释）。**判据宽容式含 42**（铁律③ + v33/v34 起七先例：功能笔
  // 编辑窗口期产出的中间构建被侧载到真机，本工程已两次实锤〔v14、v34——补账注释在上〕；
  // 停在 42 且列缺失的库若只写 `=== 41`，本分支永不进 → 摘要查询投影含 coversToSeq 列会
  // 直接抛 SQL 错）。**无数据回填**（DEFAULT NULL 即「无摘要」存量语义）。中断重跑幂等
  //（铁律①②）：ALTER 前 columnExists 守卫，重跑跳过
  if (db.version === 41 || db.version === 42) {
    if (!(await columnExists(db, 'messages', 'coversToSeq'))) {
      await db.executeSql('ALTER TABLE messages ADD COLUMN coversToSeq INTEGER DEFAULT NULL');
    }
    if (db.version === 41) {
      db.version = 42;
    }
  }
  // v42/v43 → v43（2026-09-23 知识库文件笔）——建 knowledge_files 表（知识条目的纯文本附件
  // 一行一件；表结构/语义与三条边界见上方 v43 版本注释与建表 SQL 注释）。**判据宽容式含 43**
  //（铁律③ + v33/v34 起八先例：功能笔编辑窗口期产出的中间构建被侧载到真机，本工程已两次实锤
  //〔v14、v34——补账注释在上〕；停在 43 且本表缺失的库若只写 `=== 42`，本分支永不进 → 文件
  // 读写与级联删会直接抛 SQL 错）。**无数据回填**（表自空起步，存量条目零附件）。中断重跑
  // 幂等（铁律①②）：CREATE ... IF NOT EXISTS 天然幂等
  if (db.version === 42 || db.version === 43) {
    await db.executeSql(SQL_CREATE_KNOWLEDGE_FILES);
    if (db.version === 42) {
      db.version = 43;
    }
  }
  // v43/v44 → v44（2026-09-23 首字耗时笔；同日自检轮补宽容判据）——token_usage_events 补
  // firstTokenMs（整轮首字耗时毫秒，语义见上方 v44 版本注释）。**判据宽容式含 44**（铁律③ +
  // v33/v34 起九先例：功能笔编辑窗口期产出的中间构建被侧载到真机——本工程已两次实锤
  //〔v14、v34，后者见 db-chain-check 场景 F〕；停在 44 且该列缺失的库若只写 `=== 43`，本分支
  // 永不进 → 账本投影含 firstTokenMs 列会直接抛 SQL 错〔气泡用量弹层与用量统计页两链全废〕）。
  // 列定义与新装建表 SQL 逐列一致；**无数据回填**（存量行恒 0 = 无该指标，面板均值分母走
  // 非 0 计数天然排除）。中断重跑幂等（铁律①②）：ALTER 前查列存在，重跑跳过。
  // ★ 该判据由 `scripts/db-chain-check.py` 场景 G 双向把关（静态关系钉 = 链尾谓词必覆盖
  // [D-1, D]；动态模拟 = 缺列库进分支补列），升 DB_VERSION 时随形自动跟
  if (db.version === 43 || db.version === 44) {
    if (!(await columnExists(db, 'token_usage_events', 'firstTokenMs'))) {
      await db.executeSql(
        'ALTER TABLE token_usage_events ADD COLUMN firstTokenMs INTEGER NOT NULL DEFAULT 0');
    }
    if (db.version === 43) {
      db.version = 44;
    }
  }
}

// v39→v40 存量回填（唯一调用点 = 上方 v40 迁移分支）：复刻升级前的可见序——旧读侧
// queryAssistants 是「内置两张抽到最前（默认第 1、控制台第 2）+ 其余 createdAt 升序」，
// 本函数按同一规则重排后逐行回写 sortOrder = 下标。确定性 = 同库同结果（排序键只有
// createdAt，同毫秒并列用 rowid 决胜），故中断重跑幂等。
// ★ 两个 id 字面量在此重复而**不 import** AssistantDb 的同名常量：ChatDb（import 本文件）
// ← AssistantDb（import ChatDb）构成本文件的模块环，坑50 红线禁在环内顶层读外部绑定；
// 两常量恒固定永不改（AssistantDb 头注释⑤⑥），三处字面量一致由 store-consistency 断言钉。
const MIGRATE_ASSISTANT_DEFAULT_ID: string = 'assistant-default';
const MIGRATE_ASSISTANT_CONSOLE_ID: string = 'assistant-console';

async function backfillAssistantSortOrder(db: relationalStore.RdbStore): Promise<void> {
  // 非内置行按 createdAt 升序收集（rowid 决胜 = 同毫秒并列的确定化，与旧读侧同序的确定化）
  const restIds: string[] = [];
  let hasDefault: boolean = false;
  let hasConsole: boolean = false;
  const result: relationalStore.ResultSet =
    await db.querySql('SELECT id FROM assistants ORDER BY createdAt ASC, rowid ASC');
  try {
    while (result.goToNextRow()) {
      const id: string = result.getString(result.getColumnIndex('id'));
      if (id === MIGRATE_ASSISTANT_DEFAULT_ID) {
        hasDefault = true;
      } else if (id === MIGRATE_ASSISTANT_CONSOLE_ID) {
        hasConsole = true;
      } else {
        restIds.push(id);
      }
    }
  } finally {
    result.close();
  }
  const ordered: string[] = [];
  if (hasDefault) {
    ordered.push(MIGRATE_ASSISTANT_DEFAULT_ID);
  }
  if (hasConsole) {
    ordered.push(MIGRATE_ASSISTANT_CONSOLE_ID);
  }
  for (const id of restIds) {
    ordered.push(id);
  }
  for (let i = 0; i < ordered.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
    predicates.equalTo('id', ordered[i]);
    await db.update(bucket, predicates);
  }
}
