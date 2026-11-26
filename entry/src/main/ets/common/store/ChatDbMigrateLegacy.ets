// v1~v45 冻结历史迁移链——写完永不改的顺序版本迁移块（2026-10-27 治理批 C1 拆分笔自
// ChatDbMigrate.ets 域级最小拆分外迁，块体逐字搬迁零逻辑改动；版本号/新装建表/图能力守卫/
// v46 起活链仍在主件——主件 migrateSchema 头部一行调用本件 migrateLegacyVersions，链尾写
// 46 后回主件续跑；两铁律「逐级 + 幂等」原文见主件头注释，v6~v45 逐版本语义注释唯一权威 =
// docs/参考-ChatDb迁移版本史.md）。依赖单向无环：本件只 import ChatDbSchema（叶子），不
// import 主件与任何业务 CRUD 件。
import { relationalStore } from '@kit.ArkData';
import {
  SQL_CREATE_ASSISTANTS, SQL_CREATE_ASSISTANT_MEMORIES,
  SQL_CREATE_ASSISTANT_MEMORIES_ASSISTANT_INDEX, SQL_CREATE_ATTACHMENT_REFS,
  SQL_CREATE_ATTACHMENT_REFS_ATTACH_INDEX, SQL_CREATE_ATTACHMENT_REFS_CONV_INDEX,
  SQL_CREATE_BRANCHES, SQL_CREATE_BRANCHES_CONV_INDEX, SQL_CREATE_GENERATION_RUNS,
  SQL_CREATE_GENERATION_RUNS_CONV_INDEX, SQL_CREATE_GRAPH_CAPABILITY, SQL_CREATE_KNOWLEDGE_BOOKS,
  SQL_CREATE_KNOWLEDGE_ENTRIES, SQL_CREATE_KNOWLEDGE_ENTRIES_BOOK_INDEX,
  SQL_CREATE_KNOWLEDGE_FILES, SQL_CREATE_MEMORIES, SQL_CREATE_MEMORIES_TIME_INDEX,
  SQL_CREATE_MEMORY_SNAPSHOTS, SQL_CREATE_MEMORY_SNAPSHOTS_INDEX, SQL_CREATE_MESSAGE_ATTACHMENTS,
  SQL_CREATE_MESSAGE_ATTACHMENTS_CONV_INDEX, SQL_CREATE_MESSAGE_ATTACHMENTS_MSG_INDEX,
  SQL_CREATE_MESSAGES_SEQ_INDEX, SQL_CREATE_PRICE_TEMPLATES, SQL_CREATE_PROMPT_TEMPLATES,
  SQL_CREATE_PROVIDER_KEYS, SQL_CREATE_PROVIDER_KEYS_INDEX, SQL_CREATE_PROVIDER_MODELS,
  SQL_CREATE_PROVIDER_MODELS_INDEX, SQL_CREATE_SKILLS, SQL_CREATE_SKILL_FILES,
  SQL_CREATE_SUMMARY_BINDINGS, SQL_CREATE_SUMMARY_BINDINGS_CONV_INDEX,
  SQL_CREATE_TOKEN_USAGE_CONV_INDEX, SQL_CREATE_TOKEN_USAGE_EVENTS,
  SQL_CREATE_TOKEN_USAGE_TIME_INDEX, SQL_CREATE_TOOL_FACTS, SQL_CREATE_TOOL_FACTS_RUN_INDEX
} from './ChatDbSchema';

// 列存在性检查（幂等守卫——ALTER 前查，铁律②）。PRAGMA table_info 为查询型 PRAGMA，
// 走 querySql（execute/executeSync 官方注明不支持 query，d.ts:7369；查询型 PRAGMA 用
// querySql 系社区多源实践，底层即 SQLite）；ResultSet 用完 close（红线）。表/列名均
// 代码内常量，无注入面
export async function columnExists(db: relationalStore.RdbStore, table: string,
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

// v1~v45 历史链总注释（随拆分笔自主件 migrateSchema 头注释随链外迁；逐级迁移约定原文留主件）：
// v1 → v2（2026-08-30 服务商管理域）——providers 补 enabled/sortOrder + 建 provider_models
// 表与索引；v1 的 providers 表从未接线（建表不落行），无数据迁移。
// v2 → v3（2026-08-30 详情页改版）——provider_models 补 enabled（存量行默认 1 = 全启用，
// 行为不变）+ providers 补余额八列（默认关/空——存量用户无感，高级页签再配）；列定义与
// 新装建表 SQL 逐列一致；无数据回填

export async function migrateLegacyVersions(db: relationalStore.RdbStore): Promise<void> {
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
  // 会话零回归）；列定义与新装建表 SQL 逐列一致；无数据回填（存量全部未加密）。
  // ★ 2026-11-17 整体退役加密会话笔：本列已转墓碑（产品码零读写、v66 迁移清零），本分支
  // 原样保留——迁移链是历史事实，回滚旧包仍需能升到 v16；勿在此补任何新语义。
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
  // v44/v45 → v45（2026-09-24 助手头像）：assistants 补 avatar 列（默认 '' = 首字圆底，
  // 存量助手零行为变化，语义见上方 v45 版本注释）。**判据宽容式含 45**（铁律③ + v33/v34
  // 起十先例：功能笔编辑窗口期产出的中间构建会被侧载到真机）。无数据回填。中断重跑幂等
  //（铁律①②）：ALTER 前查列存在，重跑跳过
  if (db.version === 44 || db.version === 45) {
    if (!(await columnExists(db, 'assistants', 'avatar'))) {
      await db.executeSql("ALTER TABLE assistants ADD COLUMN avatar TEXT NOT NULL DEFAULT ''");
    }
    if (db.version === 44) {
      db.version = 45;
    }
  }
  // v45/v46 → v46（2026-09-26 消息架构整合笔2——分支存储与兼容准备）：图侧 schema 准备
  //（六表六索引 + 三表补列 + capability 写 level 1；语义与 J0 红线见上方 v46 版本注释）。
  // **判据宽容式含 46**（铁律③ + v33/v34 起十一先例）。messages 五列 parentMessageId 列
  // 有意无约束（NULL = 根节点语义）；**零数据回填、零构图**（J0——本笔不迁移任何真实
  // 会话，构图迁移器只在隔离库验证）。中断重跑幂等（铁律①②）：ALTER 前 columnExists
  // 守卫、CREATE IF NOT EXISTS 天然幂等、capability 写 INSERT OR IGNORE 幂等且不降级
  //（★ 2026-09-26 自检位B 修复：原 OR REPLACE 每次冷启动把 level 2 覆写回 1——明细见块内）。
  // ★ db-chain-check 场景 H 动态把关（缺列库进分支补列 + 重跑幂等 + level 终态 1）
  if (db.version === 45 || db.version === 46) {
    if (!(await columnExists(db, 'messages', 'parentMessageId'))) {
      await db.executeSql('ALTER TABLE messages ADD COLUMN parentMessageId TEXT DEFAULT NULL');
    }
    if (!(await columnExists(db, 'messages', 'runId'))) {
      await db.executeSql("ALTER TABLE messages ADD COLUMN runId TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'messages', 'ownerAssistantId'))) {
      await db.executeSql(
        "ALTER TABLE messages ADD COLUMN ownerAssistantId TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'messages', 'stepIndex'))) {
      await db.executeSql('ALTER TABLE messages ADD COLUMN stepIndex INTEGER DEFAULT NULL');
    }
    if (!(await columnExists(db, 'messages', 'origin'))) {
      await db.executeSql("ALTER TABLE messages ADD COLUMN origin TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'conversations', 'activeBranchId'))) {
      await db.executeSql(
        "ALTER TABLE conversations ADD COLUMN activeBranchId TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'conversations', 'migrateState'))) {
      await db.executeSql(
        "ALTER TABLE conversations ADD COLUMN migrateState TEXT NOT NULL DEFAULT 'legacy'");
    }
    if (!(await columnExists(db, 'token_usage_events', 'runId'))) {
      await db.executeSql("ALTER TABLE token_usage_events ADD COLUMN runId TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'token_usage_events', 'attemptId'))) {
      await db.executeSql(
        "ALTER TABLE token_usage_events ADD COLUMN attemptId TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'token_usage_events', 'branchId'))) {
      await db.executeSql(
        "ALTER TABLE token_usage_events ADD COLUMN branchId TEXT NOT NULL DEFAULT ''");
    }
    if (!(await columnExists(db, 'token_usage_events', 'requestId'))) {
      await db.executeSql(
        "ALTER TABLE token_usage_events ADD COLUMN requestId TEXT NOT NULL DEFAULT ''");
    }
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
    // ★ 2026-09-26 自检位B 修复：INSERT OR REPLACE → INSERT OR IGNORE。本分支判据宽含 46
    //（重跑幂等），即已升级库每次冷启动都重入本块；OR REPLACE 会把笔3 迁移触发写入的
    // level 2 **无条件覆写回 1**，K2「只升不降／不允许已构图库仍标低级」与守卫②的
    // fail-closed（笔2 包拒开 capability 2 库）双双失效。OR IGNORE：行在（含 2）零写，
    // 行缺（首升 45→46）才补 1——与本块「schema 已备图未开启」初态语义一致
    await db.executeSql("INSERT OR IGNORE INTO graph_capability (id, level) VALUES ('graph', 1)");
    if (db.version === 45) {
      db.version = 46;
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
