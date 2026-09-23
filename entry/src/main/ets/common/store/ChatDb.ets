// 聊天存储层（2026-08-29 任务书 M1 新增）：relationalStore（官方 SQLite）。
// 表结构 v44（版本史/建表 SQL/迁移细则单一来源 = ChatDbMigrate.ets 头注释）：conversations
// + messages + providers（v2 起多服务商接线，CRUD 在 ProviderDb.ets；余额在
// ProviderBalanceDb.ets）+ provider_models（CRUD 在 ProviderDb.ets）+
// provider_keys（多 Key 池，行读写
// 在 ProviderKeyDb.ets；★key 明文禁落 DB——表只存元数据，明文在 Asset，见 KeyStore）+
// token_usage_events（v18 用量账本，v44 补 firstTokenMs 首字耗时列；行读写与聚合在
// UsageStatsDb.ets；删会话级联在本文件
// deleteConversations 事务内）+ message_attachments（v23 附件元数据，行读写与收敛在
// AttachmentDb.ets；级联删挂本文件 deleteConversations 与 AssistantDb.
// deleteAssistantCascade 两入口）+ prompt_templates（提示词模板库，行读写与删除级联在
// PromptTemplateDb.ets）+ assistants（助手域，行读写与级联删在 AssistantDb.ets）+
// memories（记忆域，行读写与生命周期在 MemoryDb.ets）+ assistant_memories（v35 助手级
// 记忆库，行读写与级联删在 MemoryDb.ets）+ price_templates（v27 价格模板，
// 行读写与级联删在 PriceTemplateDb.ets）+ skills / skill_files（v30 技能层两表，行读写与
// 删技能联动清列在 SkillDb.ets；skill_files 笔 1 建表零读写、笔 2 消费）+
// knowledge_books / knowledge_entries / knowledge_files（v38 知识库两表——库本体与条目〔v39
// 补 source 来源列：
// 'user' 用户写 / 'assistant' 助手写，只在 create 时定〕；v43 增第三条目附件表
// knowledge_files〔一行一条目的纯文本附件，挂条目、只存文本、不进检索索引与注入块〕，
// 行读写、删库级联与
// 清助手引用在 KnowledgeDb.ets；纯函数在 KnowledgeText.ets）+
// memory_snapshots（v41 记忆优化历史快照，行读写与整库恢复在 MemoryDb.ets；不进导出清单）。
// 版本号走 store.version
//（官方升降级姿势 = PRAGMA user_version 等价物；只加不改，迁移钩子与建表 SQL 在
// ChatDbMigrate.ets——两条铁律「逐级 + 幂等」见该文件头注释）。
// 红线落实：①DB 在沙箱（getRdbStore 默认 context.databaseDir/rdb/）；②初始化异步，由
// EntryAbility 发起，UI 经 whenReady() 等待，未就绪禁发送；③流式增量不落库，消息完成/
// 停止/出错才一次性 finalizeMessage；④消息查询一律 LIMIT（尾部 50 条/翻页每页 50；
// 会话列表 2026-09-04 决明拍板改全量 = 本条例外，行轻自然有界——见 queryConversations
// 注释）；⑤启动时 streaming
// 态一律改 error（中断恢复，不永远转圈）；⑥ResultSet 用完 close（官方要求）。
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ensureSchema, migrateSchema } from './ChatDbMigrate';
import { backfillMessageSeq, nextRowSeq, seedMessageSeq } from './MessageSeqDb';
import { countAttachmentsByConversation, deleteAttachmentsByIds,
  deleteAttachmentsForConversations, deleteAttachmentsForMessages, insertAttachments,
  AttachmentGroupRow, AttachmentListRow, AttachmentTotalRow, MessageAttachmentRow,
  queryAttachmentGroups as queryAttachmentGroupRows,
  queryAttachmentTotal as queryAttachmentTotalRow,
  queryAttachmentsByConversation as queryAttachmentRowsByConversation,
  queryAttachmentsForMessages as queryAttachmentRowsForMessages,
  removeAttachmentFiles } from './AttachmentDb';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatDb';
const DB_NAME: string = 'aicontrol.db';
// 会话 id 兜底值（ChatPage 结构缺省——正常链路 id 均由 push/replace 注入；该 id 无预建行，
// 发送时经 ensureConversation 懒建，「空会话不进历史」语义统一管辖）
export const DEFAULT_CONVERSATION_ID: string = 'conv-default';
// 消息查询上限（任务书：首次拉尾部 50 条）
export const QUERY_TAIL_LIMIT: number = 50;

// 待落行加密会话标记（2026-09-05 会话页更多菜单「加密会话」新建链）：运行时非持久键，
// 值 = 认证通过后新建的会话 id（nextMessageId 全局唯一不复用——残留键永不误命中，无害）。
// 写点 = ChatPage.newEncryptedConversation（biometricGate 通过后）；消费点 = ensureConversation
// 首条消息落行时 id 匹配则 locked=1 并清键——空会话退出不落行 = 标记自然失效（历史无痕），
// 有消息落行 = locked 随行入列（列表锁标与再进验证走既有链）
export const PENDING_LOCKED_CONV_KEY: string = 'pendingLockedConvId';

export interface ConversationRow {
  id: string;
  title: string;
  providerId: string;
  createdAt: number;
  updatedAt: number;
  // 加密标记（2026-09-04 v16，加密会话）：true = 进会话页需先通过官方生物识别（卡片
  // 显示锁标）；只改进入门禁，消息产生/读写/存储链路零改动——语义见 ChatDbMigrate v16 注释
  locked: boolean;
  // 标题来源三态（2026-09-05 v17，AI 会话标题自动生成）：'' = 占位（首条消息升级为
  // 截断占位标题，AI 回复完成后触发生成）/ 'ai' = AI 已生成（成功即止）/ 'manual' =
  // 用户手改（生成链两道守卫见此即放弃）——语义见 ChatDbMigrate v17 注释与 TitleGen.ets
  titleSource: string;
  // 收藏标记（2026-09-08 v19，会话搜索与收藏）：true = 收藏（卡片星标 + 「全部/收藏」
  // 分段过滤）；只改标记列不动 updatedAt（收藏不改变列表时间序）——语义见 ChatDbMigrate
  // v19 注释
  favorite: boolean;
}

export interface MessageRow {
  id: string;
  conversationId: string;
  role: string; // user / assistant / tool
  content: string;
  reasoning: string;
  status: string; // streaming / done / error
  createdAt: number;
  // 行物理序（2026-09-19 乱序修复笔）：查询投影带回、插入路径不带（rowid 由库自派）。
  // ★ 2026-09-21 笔 3 切序后**读取面消费面归零**（原消费面 = 翻页游标决胜键 MessageCursor）：
  // 列仍随两种显式投影带回、机制不退役（D5——退役族整体偿还时机 = 本笔上线稳定一轮后另笔）
  rowid?: number;
  // ── 多版本（DB v36，2026-09-20 消息重新生成）：仅 assistant 行有意义；'' / 缺省 =
  // 单版消息（从未重试）。variants 为全量真源 JSON 串（结构与读写口单源 =
  // MessageVariantDb.ets 域件；语义总纲 = ChatDbMigrate v36 版本注释），content 列恒存
  // 选中版内容（投影——现役读方零改动的关键）；variantActive = 选中下标。查询投影带回
  //（queryRecentMessages / queryMessagesBefore）；插入路径不带（首答无版本）
  variants?: string;
  variantActive?: number;
  // ── 会话内显式序号（DB v37 seq 列；2026-09-21 笔 2 写入 / 笔 3 读取权威）──
  // 由**写入侧分配器**在构造行对象的同步点铸造（MessageSeqDb.nextRowSeq，会话内 0 基递增；
  // D1 红线见该域件头注释）。可选 = 防御性兜底（undefined ⇒ insertMessage 不写本列、落 NULL，
  // 由启动补号 sweep 与导入即时补号兜底）；**产品写入点一律必铸**（七处逐点钉在
  // assert-store-consistency 144 组）。★ 笔 3 起查询投影带回（两处显式投影）+ 排序权威
  //（三个单会话读窗口与翻页游标切 seq；跨会话检索窗**禁切**——排序键作用域判据见
  // searchMessagesAcross 注释）——「投影不带、读取仍 createdAt 序」旧口径随之消失
  seq?: number;
  // ── 压缩摘要覆盖边界（DB v42；仅 summary 行有意义——组装裁段判据，写入唯一点 CompressDb）
  coversToSeq?: number;
}

export interface ProviderModelRow {
  id: string;
  providerId: string;
  modelId: string;
  name: string;
  kind: string; // 'chat'（对话）/ 'embedding'（向量）
  caps: string; // 能力码逗号串（'tool,reason,web,vision,image' 子集）
  createdAt: number;
  enabled: boolean; // v3：模型级启停（停用不进选择面板与连接解析）
  // v15（2026-09-03 Cube 吸收 A1）：能力派生/覆盖标志——false = 未手改，caps 展示与
  // 消费走 effectiveCaps 读时按模型名派生（ModelRegistry，规则升级自动跟随，派生值
  // 不落库）；true = 用户手改固化，caps 原样生效（含显式全不勾）
  capsUserModified: boolean;
  // v21（2026-09-08 模型选择半模态优化）：模型收藏标记——true = 选择面板行内爱心点亮 +
  // 「全部/收藏」分段可见；随模型行同生命周期（删模型/删服务商/取消勾选即随行清除）；
  // 本机语义，单家分享不携带（语义见 ChatDbMigrate v21 注释）
  favorite: boolean;
  // v27（2026-09-10 费用估计）：价格 JSON 串（'' = 未配置；单位 = 元/百万 tokens）。
  // 字段结构与解析/序列化单一来源 = common/store/CostStatsCalc.ets（parsePriceConfig /
  // serializePriceConfig）——本注释不复制结构防双源。消费面 = 费用估计页折算；随模型行
  // 同生命周期，全量备份 SELECT * 自动携带
  priceConfig: string;
  // v33（2026-09-17 模型上下文窗口配置）：上下文窗口 token 数——0 = 未配置 = 跟随内置
  // 参考值（ModelRegistry.lookupContextBaseline 读时按模型名派生，参考值不落库）；非 0 =
  // 用户覆盖值。与能力链「派生不落库 / 覆盖落库」同构（caps_user_modified 家族）。★ 本笔
  // 无消费面：历史裁剪/用量占比/请求组装/费用估计一律不读本列
  contextWindow: number;
}

let store: relationalStore.RdbStore | null = null;
let initPromise: Promise<boolean> | null = null;
let idSeq: number = 0;

// 消息 id 生成（keyGenerator 用——稳定唯一，禁用数组下标）
export function nextMessageId(prefix: string): string {
  idSeq++;
  return prefix + '-' + Date.now() + '-' + idSeq;
}

// 消息行 createdAt 单调分配器（2026-09-19 工具卡回放乱序修复笔）：当时回放序 = createdAt 序，
// 历史落库笔「工具行收尾与下一轮 assistant 占位行同一同步链取 Date.now()」同毫秒并列后，
// 重进回放序取决于物理插入序——真机实锤「工具卡显示在最新消息后」。契约 = 同进程内每次
// 调用严格大于上一次（撞毫秒 +1 让位），行间逻辑先后完全由调用序表达，并列从源头消失。
// 接入点 = **全部产品消息写入点**（2026-09-21 消息存储机制改造笔 2 收口：原「ChatSendCtrl
// 发送对裸 now/now+1 与 ProactiveGen 未接」两处已并入，该口径消失）；残留同毫秒（跨进程/
// 旧数据）由启动幂等修复清扫兜底（repairTiedMessageTimestamps——查询侧 rowid 决胜键已随笔 3
// 切序退役）。★ 笔 3：显示序权威归 seq，本分配器消费面收窄为时间显示与修复器取值
let lastRowCreatedAt: number = 0;

export function nextRowCreatedAt(): number {
  const now: number = Date.now();
  lastRowCreatedAt = now > lastRowCreatedAt ? now : lastRowCreatedAt + 1;
  return lastRowCreatedAt;
}

// 初始化（EntryAbility 阶段调用一次；幂等——重复调用复用同一 Promise）
export function initChatDb(context: common.UIAbilityContext): Promise<boolean> {
  if (initPromise !== null) {
    return initPromise;
  }
  initPromise = doInit(context);
  return initPromise;
}

// UI 等待就绪（EntryAbility 必先于页面执行，initPromise 必已建；双保险兜底 false）
export function whenReady(): Promise<boolean> {
  return initPromise !== null ? initPromise : Promise.resolve(false);
}

export function isReady(): boolean {
  return store !== null;
}

async function doInit(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const rdb: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    // 新装建表 + 版本迁移（2026-08-30 自本文件拆至 ChatDbMigrate——迁移幂等化后行数超
    // 400 红线，域级最小拆分；新装/迁移两条铁律「逐级 + 幂等」见该文件头注释）
    await ensureSchema(rdb);
    await migrateSchema(rdb);
    store = rdb;
    // 空会话清扫（2026-08-29「空会话不进历史」配套）：删除无任何消息的会话行——清掉
    // 懒创建语义启用前的存量垃圾（预建新会话/默认会话空行）；此后空行不再产生（懒创建），
    // 本清扫仅启动跑一次。默认会话行不再预建（原 ensureDefaultConversation 已删——空行
    // 与本语义冲突）；对话页兜底 id（conv-default）发送时经 ensureConversation 懒建
    await sweepEmptyConversations();
    // 中断恢复：上次退出残留 streaming 态一律改 error（不永远转圈）
    await markStreamingAsError();
    // 并列修复清扫（2026-09-19 乱序修复笔；★ 2026-09-21 回退并列门，见被调函数注释——
    // 幂等启动维护，空会话清扫先例）
    await repairTiedMessageTimestamps();
    // seq 补号清扫（2026-09-21 消息存储机制改造笔 1；幂等启动维护第 4 件，实现与规则在
    // MessageSeqDb.ets 消息序号域——含 NULL 或缺号/重号的会话整会话重算，稳态零写）。
    // ★ 时序前提：必须在 migrateSchema 之后（同一次首启内先建列再回填——本行在 doInit 内
    // 位于 ensureSchema/migrateSchema 之后，天然满足）；句柄传 rdb（域件不 import 本件，
    // 零环——见 MessageSeqDb 头注释依赖方向）
    await backfillMessageSeq(rdb);
    // seq 分配器播种（2026-09-21 消息存储机制改造笔 2）：写入侧分配器（MessageSeqDb 域件）
    // 的进程内记账从库中真值回读——**必须在补号 sweep 之后**（sweep 先把残缺号归一，播种读
    // 修复后的真值；顺序对调 = 本次启动的记账按未修复值起步，与 848「并列修复先于 seq 补号」
    // 同族的启动时序面）。失败上抛 → 本函数捕获返假 → UI 报初始化失败（不静默）
    await seedMessageSeq(rdb);
    hilog.info(DOMAIN, TAG, 'ChatDb 初始化完成');
    return true;
  } catch (e) {
    const biz = e as BusinessError;
    hilog.error(DOMAIN, TAG, 'ChatDb 初始化失败：code %{public}d %{public}s',
      typeof biz.code === 'number' ? biz.code : -1, (e as Error).message);
    return false;
  }
}

function requireStore(): relationalStore.RdbStore {
  if (store === null) {
    throw new Error('数据库未就绪');
  }
  return store;
}

// 共享库句柄（ProviderDb.ets 服务商域 CRUD 消费——同一 aicontrol.db 单一初始化源；
// 未就绪同样抛错，调用侧 whenReady 守卫语义一致）
export function sharedRdbStore(): relationalStore.RdbStore {
  return requireStore();
}

// 拉尾部最近 N 条（升序返回——查询侧降序 LIMIT 再反转，保证「尾部 + 时间序」）。
// 查询直写（RdbPredicates 无 rowid/seq 投影能力——queryMessagesBefore 直写先例）。
// ★ 2026-09-21 笔 3 切序：ORDER BY createdAt DESC, rowid DESC → **seq DESC 单键**（读取权威
// = 会话内显式序号，seq 会话内互异 ⇒ 决胜机制无消费面）；rowid 仍随投影带回（D5 不退役；
// ★ 2026-09-23 压缩：投影尾补 coversToSeq——NULL → 缺省 = 无摘要）
export async function queryRecentMessages(conversationId: string): Promise<MessageRow[]> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT id, conversationId, role, content, reasoning, status, createdAt, rowid, seq, ' +
    'variants, variant_active, coversToSeq FROM messages ' +
    'WHERE conversationId = ? ORDER BY seq DESC LIMIT ?',
    [conversationId, QUERY_TAIL_LIMIT]);
  const rows: MessageRow[] = [];
  try {
    while (result.goToNextRow()) {
      const row: MessageRow = {
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        role: result.getString(result.getColumnIndex('role')),
        content: result.getString(result.getColumnIndex('content')),
        reasoning: result.getString(result.getColumnIndex('reasoning')),
        status: result.getString(result.getColumnIndex('status')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        rowid: result.getLong(result.getColumnIndex('rowid')),
        seq: result.getLong(result.getColumnIndex('seq')),
        variants: result.getString(result.getColumnIndex('variants')),
        variantActive: result.getLong(result.getColumnIndex('variant_active'))
      };
      row.coversToSeq = result.isColumnNull(result.getColumnIndex('coversToSeq')) ? undefined : result.getLong(result.getColumnIndex('coversToSeq'));
      rows.push(row);
    }
  } finally {
    result.close();
  }
  rows.reverse();
  return rows;
}

// 触顶翻页游标（2026-08-31 任务 D）：当前窗口最早消息行的**会话内 seq**（单键，0 基）。
// ★ 2026-09-21 笔 3 单键化：原 createdAt+rowid 双键退役（决胜理由 = 时间戳同毫秒并列，而
// seq 由分配器与回填保证会话内互异 ⇒ 读取面不再需要决胜）；语义 = 「更早 = seq 更小」
export interface MessageCursor {
  seq: number;
}

// 查询早于游标的一页消息（2026-08-31 触顶翻页）：降序取 QUERY_TAIL_LIMIT 条再反转升序
// ——与 queryRecentMessages 同口径（每页 50 有界，禁止无界连拉）；到底返回空数组 =
// 调用方终止条件。★ 2026-09-21 笔 3 切序：条件收窄为 **seq 单键**（`seq < ?`）、排序即 seq 序
//（翻页与尾窗同源；直写保留因投影含 rowid/seq 双列）
export async function queryMessagesBefore(conversationId: string,
  cursor: MessageCursor): Promise<MessageRow[]> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT id, conversationId, role, content, reasoning, status, createdAt, rowid, seq, ' +
    'variants, variant_active, coversToSeq FROM messages ' +
    'WHERE conversationId = ? AND seq < ? ' +
    'ORDER BY seq DESC LIMIT ?',
    [conversationId, cursor.seq, QUERY_TAIL_LIMIT]);
  const rows: MessageRow[] = [];
  try {
    while (result.goToNextRow()) {
      const row: MessageRow = {
        id: result.getString(result.getColumnIndex('id')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        role: result.getString(result.getColumnIndex('role')),
        content: result.getString(result.getColumnIndex('content')),
        reasoning: result.getString(result.getColumnIndex('reasoning')),
        status: result.getString(result.getColumnIndex('status')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        rowid: result.getLong(result.getColumnIndex('rowid')),
        seq: result.getLong(result.getColumnIndex('seq')),
        variants: result.getString(result.getColumnIndex('variants')),
        variantActive: result.getLong(result.getColumnIndex('variant_active'))
      };
      row.coversToSeq = result.isColumnNull(result.getColumnIndex('coversToSeq')) ? undefined : result.getLong(result.getColumnIndex('coversToSeq'));
      rows.push(row);
    }
  } finally {
    result.close();
  }
  rows.reverse();
  return rows;
}

// 跨会话消息检索候选行（2026-09-13 跨会话检索笔，search_chats 工具预筛面——四字段轻行，
// id/reasoning/status 不取）：conversationId 供标题反查与「来自几个会话」统计，role 供
// 结果行角色标注；打分/排序/片段纯函数在 providers/ToolChatSearch（本接口是其入参类型）
export interface ChatMessageHitRow {
  conversationId: string;
  role: string;
  content: string;
  createdAt: number;
}

// 跨会话消息检索（同上笔，方案-跨会话检索-20260913 §2.3；消费方 = ToolChatSearch
// SearchChatsExecutor）：LIKE 每词一式 OR 预筛（patterns 由调用侧纯函数产——已含 %
// 包裹与通配符转义，ESCAPE '\' 配对）→ locked 会话 join 排除（加密内容不得经检索流入
// 普通上下文，沉淀链同款守卫）→ 当前会话排除（'' = 无排除；「其他会话」语义）→
// user/assistant 行（tool/notice 行不入检索面）→ 最近 limit 条命中（createdAt DESC 保
// 最近命中，相关度重排在调用侧端内做）。RdbPredicates 无 JOIN 与 OR 组合能力，querySql
// 直写（queryMessagesBefore 先例）；本地 RDB 千行级 LIKE 全扫毫秒级，FTS 留二期。
// ★ 2026-09-21（笔 3 切序 → 自检 P1 拍板回退）：本窗口**禁切 seq**——判据 = 排序键的作用域
// 必须覆盖扫描域：seq 是**会话内** 0 基序号（每个会话各自从 0 起铸、换会话即重置），本查询却是
// JOIN **全库混排 ＋ LIMIT 截断** ⇒ 排序键即**候选集成员判据**，切成 `m.seq DESC` 后「全库最近
// 300 条命中」退化成「各会话内序号最大的那批」：短会话（新建/聊得少的）命中被系统性挤出候选集，
// 用户刚在新会话聊过的内容搜不到且零报错（执行级实证：405 命中 / LIMIT 300 ⇒ 新会话命中 0 条）。
// 同笔其余三窗口皆为单会话查询（扫描域 == 序号域）⇒ 切序真等价，分野正是本判据。
// 排序权威维持 `m.createdAt DESC, m.rowid DESC`（rowid 决胜 = 同毫秒并列的确定化，笔 1 补）
export async function searchMessagesAcross(patterns: string[], excludeConversationId: string,
  limit: number): Promise<ChatMessageHitRow[]> {
  if (patterns.length === 0) {
    return [];
  }
  const likeSql: string[] = patterns.map((_p: string): string => "m.content LIKE ? ESCAPE '\\'");
  const args: Array<string | number> = [excludeConversationId];
  for (const pattern of patterns) {
    args.push(pattern);
  }
  args.push(limit);
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT m.conversationId, m.role, m.content, m.createdAt FROM messages m ' +
    'JOIN conversations c ON m.conversationId = c.id ' +
    'WHERE c.locked = 0 AND m.conversationId <> ? AND m.role IN (\'user\', \'assistant\') ' +
    'AND (' + likeSql.join(' OR ') + ') ' +
    'ORDER BY m.createdAt DESC, m.rowid DESC LIMIT ?', args);
  const rows: ChatMessageHitRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        role: result.getString(result.getColumnIndex('role')),
        content: result.getString(result.getColumnIndex('content')),
        createdAt: result.getLong(result.getColumnIndex('createdAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// ── 跨会话读取查询（2026-09-19 跨会话记忆深化笔，get_chats 工具；消费方 = ToolChatSearch
// GetChatsExecutor）：三查询全部 SQL 层 locked = 0 硬排除（加密会话内容不得经工具流出——
// 跨会话读取域八闸①）+ 当前会话排除（「其他会话」语义，searchMessagesAcross 同款）。
// 行类型轻列（不取无关列）；全部有界（LIMIT/COUNT 单查），禁逐行查（P1-2）。
// ★ 升序窗口口径：queryConversationWindowForRead 的 startOneBased = 窗口首条在全会话
// user/assistant 消息中按 **seq 升序** 的全局序号（1 基），OFFSET = start - 1——任务书
// §2.2 SQL 串原文写 DESC 与「窗口 OFFSET = offset - 1」「offset=1 读更早」三者在 DESC 下
// 互斥、唯 ASC 自洽，按语义落 ASC（偏差已在变更记录点名）；★ 2026-09-21 笔 3 切序后位次
// 语义不变——COUNT 与窗口两查询筛选面完全一致（同 locked/角色条件），位次只依赖行集与
// 排序键，换键不影响「第 N 条」的算法。

// 会话轻行（list 清单与标题定位共用——三列恰为渲染所需）
export interface ChatReadConvRow {
  id: string;
  title: string;
  updatedAt: number;
}

// 消息窗行（read 通读——三列恰为渲染所需，id/reasoning/status 不取）
export interface ChatReadWindowRow {
  role: string;
  content: string;
  createdAt: number;
}

// 最近会话清单（list 动作）：locked 排除 + 当前会话排除（excludeId '' = 无排除——执行器
// 中转键空值兜底，同 searchMessagesAcross），updatedAt DESC 限 limit
export async function queryRecentConversationsForRead(limit: number,
  excludeConversationId: string): Promise<ChatReadConvRow[]> {
  let sql: string = 'SELECT id, title, updatedAt FROM conversations WHERE locked = 0';
  const args: Array<string | number> = [];
  if (excludeConversationId !== '') {
    sql += ' AND id <> ?';
    args.push(excludeConversationId);
  }
  sql += ' ORDER BY updatedAt DESC LIMIT ?';
  args.push(limit);
  const result: relationalStore.ResultSet = await requireStore().querySql(sql, args);
  const rows: ChatReadConvRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        title: result.getString(result.getColumnIndex('title')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 标题精确定位（read 动作）：locked 排除 + title 精确等值（trim 在执行器侧做）；多行 =
// 同名歧义（执行器拒歧义），行空 = 0 命中（执行器回名单引导重试）
export async function queryConversationIdByTitle(title: string): Promise<ChatReadConvRow[]> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT id, title, updatedAt FROM conversations WHERE locked = 0 AND title = ?', [title]);
  const rows: ChatReadConvRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        title: result.getString(result.getColumnIndex('title')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 消息窗行数（read 动作前置 COUNT——窗口起点归一需总数先行，与窗口查询同形 WHERE：
// locked 排除 + user/assistant 行；两查询有界，本地毫秒级）
export async function countConversationMessagesForRead(conversationId: string): Promise<number> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COUNT(*) AS n FROM messages m JOIN conversations c ON m.conversationId = c.id ' +
    'WHERE m.conversationId = ? AND c.locked = 0 AND m.role IN (\'user\', \'assistant\')',
    [conversationId]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 消息窗查询（read 动作）：升序窗口 LIMIT ? OFFSET ?（startOneBased 归一在执行器纯函数
// resolveChatReadStart——业务语义不入 store 层）；locked 排除 + user/assistant 行
//（tool/notice 行不入读取面，searchMessagesAcross 同口径）。
// ★ 2026-09-21（笔 1 补 rowid 决胜 → 笔 3 切序）：排序权威 = **seq 单键**——原
// `m.createdAt ASC, m.rowid ASC` 双键退役（同毫秒并列行的窗口切点由不定转确定的收口随读取
// 权威切换失去意义：seq 会话内互异）；O3 遗留面（可变排序键 × OFFSET 位置分页）由本次换键
// 一并缓解——seq 除重试置尾与导入补号外不改写，且两处均与行序推进同向
export async function queryConversationWindowForRead(conversationId: string,
  startOneBased: number, limit: number): Promise<ChatReadWindowRow[]> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT m.role, m.content, m.createdAt FROM messages m ' +
    'JOIN conversations c ON m.conversationId = c.id ' +
    'WHERE m.conversationId = ? AND c.locked = 0 AND m.role IN (\'user\', \'assistant\') ' +
    'ORDER BY m.seq ASC LIMIT ? OFFSET ?',
    [conversationId, limit, startOneBased - 1]);
  const rows: ChatReadWindowRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        role: result.getString(result.getColumnIndex('role')),
        content: result.getString(result.getColumnIndex('content')),
        createdAt: result.getLong(result.getColumnIndex('createdAt'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 会话消息统计行（2026-09-19 会话统计半模态笔）：单行聚合——三角色计数 + 首末时间。
// 口径：user/assistant 为「对话消息」（消息总数 = 两者和），tool 卡单列「工具调用」，
// notice 提示条不入统计；首末时间只取 user/assistant 行（时间跨度与消息总数同基）。
// 空会话各值为 0 = 真零（面板时间卡以 firstAt 0 判「无行不显」）；查询异常由调用方
// 降级（0 与未知区分同面板既有口径）
export interface ConversationMsgStats {
  userCount: number;
  assistantCount: number;
  toolCount: number;
  firstAt: number;
  lastAt: number;
}

export async function conversationMsgStats(conversationId: string): Promise<ConversationMsgStats> {
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT IFNULL(SUM(CASE WHEN role = \'user\' THEN 1 ELSE 0 END), 0) AS u, ' +
    'IFNULL(SUM(CASE WHEN role = \'assistant\' THEN 1 ELSE 0 END), 0) AS a, ' +
    'IFNULL(SUM(CASE WHEN role = \'tool\' THEN 1 ELSE 0 END), 0) AS t, ' +
    'IFNULL(MIN(CASE WHEN role IN (\'user\', \'assistant\') THEN createdAt END), 0) AS f, ' +
    'IFNULL(MAX(CASE WHEN role IN (\'user\', \'assistant\') THEN createdAt END), 0) AS l ' +
    'FROM messages WHERE conversationId = ?', [conversationId]);
  const stats: ConversationMsgStats = { userCount: 0, assistantCount: 0, toolCount: 0,
    firstAt: 0, lastAt: 0 };
  try {
    if (result.goToNextRow()) {
      stats.userCount = result.getLong(result.getColumnIndex('u'));
      stats.assistantCount = result.getLong(result.getColumnIndex('a'));
      stats.toolCount = result.getLong(result.getColumnIndex('t'));
      stats.firstAt = result.getLong(result.getColumnIndex('f'));
      stats.lastAt = result.getLong(result.getColumnIndex('l'));
    }
  } finally {
    result.close();
  }
  return stats;
}

// 候选行会话标题批量反查（同上笔；与检索同一消费方）：IN 集去重一次查回——两查询有界，
// 禁逐行查（P1-2）；行缺失（理论不发生——JOIN 已保证）不进 Map，调用侧回「未命名会话」
export async function queryConversationTitles(rows: ChatMessageHitRow[]): Promise<Map<string, string>> {
  const ids: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const row of rows) {
    if (!seen.has(row.conversationId)) {
      seen.add(row.conversationId);
      ids.push(row.conversationId);
    }
  }
  const titles: Map<string, string> = new Map<string, string>();
  if (ids.length === 0) {
    return titles;
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('conversations');
  predicates.in('id', ids);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id', 'title']);
  try {
    while (result.goToNextRow()) {
      titles.set(result.getString(result.getColumnIndex('id')),
        result.getString(result.getColumnIndex('title')));
    }
  } finally {
    result.close();
  }
  return titles;
}

// 会话列表（2026-08-29 M2a 领导指令：对话页签改历史会话，点卡片进对话页）——按最近
// 更新倒序，**全量查询**（2026-09-04 决明拍板：本地 RDB 查全量毫秒级，会话行轻、规模
// 自然有界——删原 QUERY_TAIL_LIMIT 50 上限与滚动加载分页，一次查全部；dshinhm 的
// 服务端分页是远程协议必然，本地库无此约束）；全列查询凑齐 ConversationRow。
// ★ 2026-09-01 会话绑定助手：按 assistantId 集过滤（历史只显示当前助手名下）——id 集
// 由 AssistantDb.historyFilterIds 给（★2026-09-04 晚定稿：'' 行 = 默认助手名下，仅默认
// 助手口径含 ''）；入参纯数组（坑6 族）
export async function queryConversations(assistantIds: string[]): Promise<ConversationRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.in('assistantId', assistantIds);
  predicates.orderByDesc('updatedAt');
  const columns: string[] = ['id', 'title', 'providerId', 'createdAt', 'updatedAt', 'locked', 'titleSource',
    'favorite'];
  const result: relationalStore.ResultSet = await requireStore().query(predicates, columns);
  const rows: ConversationRow[] = [];
  try {
    while (result.goToNextRow()) {
      const row: ConversationRow = {
        id: result.getString(result.getColumnIndex('id')),
        title: result.getString(result.getColumnIndex('title')),
        providerId: result.getString(result.getColumnIndex('providerId')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
        locked: result.getLong(result.getColumnIndex('locked')) === 1,
        titleSource: result.getString(result.getColumnIndex('titleSource')),
        favorite: result.getLong(result.getColumnIndex('favorite')) === 1
      };
      rows.push(row);
    }
  } finally {
    result.close();
  }
  return rows;
}

// 会话加密标记写值（2026-09-04 加密会话，菜单「加密会话/解除加密」唯一落点——调用侧
// 已通过官方生物识别才走到这里）：只改标记列，不动 updatedAt（加密不改变列表时间序）
export async function setConversationLocked(id: string, locked: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'locked': locked ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 会话收藏标记写值（2026-09-08 会话搜索与收藏，菜单「收藏/取消收藏」唯一落点）：只改
// 标记列，不动 updatedAt（收藏不改变列表时间序，setConversationLocked 同口径）
export async function setConversationFavorite(id: string, favorite: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'favorite': favorite ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 启动清扫空会话行（2026-08-29「空会话不进历史」配套，见 doInit 注释）：NOT IN 反连接
// 一条 SQL——RdbPredicates 无子查询能力，executeSql 直写（无 bindArgs 数参，坑6 族无暴露）；
// 无消息会话行删、其 messages 天然无（空行定义），不涉事务。
// ★ 子查询带 `conversationId IS NOT NULL`（2026-09-22 自检轮族收口）：反连接的 NULL 语义坑——
// 子查询结果集里只要出现一个 NULL，`id NOT IN (...)` 对整个外层就不是真（三值逻辑）⇒
// 清扫对所有会话静默失效（空会话行只增不减），而这类 NULL 值由同族的「备份缺 id 键」数据
// 引入（见 MessageSeqDb 头注释 856 条）。NULL conversationId 的 messages 行本就不属任何
// 会话行，排除它不影响判定
async function sweepEmptyConversations(): Promise<void> {
  await requireStore().executeSql('DELETE FROM conversations WHERE id NOT IN ' +
    '(SELECT DISTINCT conversationId FROM messages WHERE conversationId IS NOT NULL)');
}

// 首条消息确保会话行存在（2026-08-29 领导指令「空会话不进历史」）：会话行不再在「新建」
// 时预建（原 createConversation 已随懒创建语义删除）——新建只本地生成 id 直接进对话页，
// 首条消息 insertMessage 时才落行。空会话（新建不发送/发前退出）在 DB 无行，历史列表
// 自然不显示，也无空行垃圾。标题固定「新对话」，时间序由 touchConversation 随首条消息
// 维护（列表置顶）。★ 2026-09-01 会话绑定助手：建行写入 assistantId（发送侧给值——
// 有效归属实体值，★2026-09-04 晚定稿后恒非 ''）；仅建行时消费，行已存在 = 查询即返零
// 开销）。★ 2026-09-04 归属与注入解耦：assistantId 与 promptId 两值同落互不清零
//（assistantId = 有效归属；promptId = 面板提示词覆盖，'' = 未启用注入）
async function ensureConversation(conversationId: string, assistantId: string,
  promptId: string = '', locked: boolean = false,
  override: ConversationOverride | null = null): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['id']);
  try {
    if (result.rowCount > 0) {
      return;
    }
  } finally {
    result.close();
  }
  const now: number = Date.now();
  const bucket: relationalStore.ValuesBucket = {
    'id': conversationId,
    'title': '新对话',
    'providerId': '',
    'assistantId': assistantId,
    'promptId': promptId,
    'createdAt': now,
    'updatedAt': now,
    'locked': locked ? 1 : 0,
    // 会话级覆盖随首发落行（2026-09-10 会话级覆盖层笔）：无行期改动只存内存，此处补写入行
    'modelProviderId': override !== null ? override.modelProviderId : '',
    'modelId': override !== null ? override.modelId : '',
    'webSearchOverride': override !== null ? override.webSearchOverride : ''
  };
  await requireStore().insert('conversations', bucket);
}

// 批量彻底删除会话（2026-08-29 会话多选删除）：messages 与 conversations 两表建表无外键
// 约束，删会话行不会级联删消息——「彻底删除」必须同事务手动两删，否则留孤儿消息永占空间。
// 事务 = beginTransaction/commit/rollBack 经典三件套（@since 9；官方《通过关系型数据库
// 实现数据持久化》指南同款姿势，本地 d.ts 核实同步方法）——先删 messages（conversationId
// IN）再删 conversations（id IN），任一步失败 rollBack 整体回滚（P0-1：不半删）。
// 返回删除的会话行数；空入参直接 0（无事务开销，兼防 in() 空数组「条件失效落全表」——
// d.ts:2388 原文）。注：默认会话（conv-default）行可删，启动清扫同样管辖（空行即清）；
// 对话页兜底 id 发送时经 ensureConversation 懒建。
// ★ v18（2026-09-06 token 用量统计）：事务内追加 token_usage_events 级联删（决明口径④
// 删会话不保留——统计页只反映现存会话）。与 messages 删除同款 predicates 一次性 in 姿势
// （会话 id 集 = 多选规模天然有界）。不调 UsageStatsDb（其 import 本文件——禁循环依赖），
// 删除口径单点在该表域注释登记
// ★ v23（2026-09-09 附件落盘第一轮）：事务内追加 message_attachments 级联删行（附件行
// 生命周期随消息——文件本体删除在 commit 后）。**级联铁律：任何新增「删 messages」路径，
// 必须在同函数同事务内删附件行**（本域建立时全仓删 messages 落点 = 本函数 +
// AssistantDb.deleteAssistantCascade 两处；sse-assert ㊽ 组 tripwire 钉 messages 谓词计数）
export async function deleteConversations(ids: string[]): Promise<number> {
  if (ids.length === 0) {
    return 0;
  }
  const db: relationalStore.RdbStore = requireStore();
  // ★ 普通数组拷贝（2026-08-29 反馈轮 3 真机实锤，坑6）：入参可能来自 @State（观察代理
  // 数组）——直传 in() 抛 401「Parameter error. The value must be a ValueType array」
  // （napi 参数校验不认观察代理）；逐元素拷进新建普通数组后通过。若后续 SDK 仍报同错，
  // 回退方案 = executeSql + IN 占位符 bindArgs（同为 ValueType 数组校验族，需同样纯数组）
  const plainIds: string[] = [];
  for (const id of ids) {
    plainIds.push(id);
  }
  const msgPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  msgPredicates.in('conversationId', plainIds);
  const usagePredicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('token_usage_events');
  usagePredicates.in('conversationId', plainIds);
  const convPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  convPredicates.in('id', plainIds);
  db.beginTransaction();
  try {
    // 附件行级联（v23）：函数内先 SELECT 收集 localPath 再删行；文件 I/O 在 commit 之后
    //（回滚不得已删文件红线——回滚后行还在，文件删了就成「行在文件不在」）
    const attachPaths: string[] = await deleteAttachmentsForConversations(db, plainIds);
    await db.delete(msgPredicates);
    await db.delete(usagePredicates);
    const deleted: number = await db.delete(convPredicates);
    db.commit();
    removeAttachmentFiles(attachPaths); // best-effort：失败留启动收敛自愈
    return deleted;
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// 重命名会话（2026-08-30 会话卡片长按菜单，领导指令「重命名参考旧项目」）：仅改标题、
// 不动 updatedAt（重命名不改变列表时间序——与旧项目服务端重命名行为一致）；非空/同值
// 校验在 InputDialog 内（空值不发、同值跳过），此处直写。★ 2026-09-05 v17：同一 UPDATE
// 内嵌 titleSource='manual'（用户手改终胜出标记——AI 生成链写回前重查见 manual 即放弃；
// 与 title 同条 UPDATE 原子落库，防「title 已改 / source 未改」中间态被生成链踩）；签名
// 不变 = 既有调用点零破坏
export async function renameConversation(id: string, title: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'title': title, 'titleSource': 'manual' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 标题写回（2026-09-05 v17 AI 会话标题自动生成）：title 与 titleSource 同条 UPDATE 原子
// 落库、**不动 updatedAt**（标题不改变列表时间序，与 renameConversation 同口径）。
// 消费方 = TitleGen 两写点——AI 写回 ('ai') 与首条占位升级 (''：title 为截断占位串，
// source 仍 '' = 占位态，AI 生成链照常触发)。调用方负责写回前重查守卫（manual 放弃）
export async function setConversationTitle(id: string, title: string, source: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'title': title, 'titleSource': source };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 占位标题条件升级（2026-09-05 v17 首条占位）：仅当行仍为「新对话 + 占位态''」才写
// 截断标题——条件谓词 UPDATE 原子闸（equalTo 链 = AND 组合），天然防两类并发覆盖
//（①已升级为占位串/AI 标题的行 title != '新对话' 不中；②极端窗口内用户已改名 =
// titleSource='manual' 不中）；同样不动 updatedAt。返回是否升级（调用方留痕用）；
// executeSql 无行数返回（d.ts Promise<void>），故走 update 谓词式（affected 先例 =
// ProviderDb.updateProviderPromptCache）
export async function upgradePlaceholderTitle(id: string, title: string): Promise<boolean> {
  const bucket: relationalStore.ValuesBucket = { 'title': title, 'titleSource': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  predicates.equalTo('title', '新对话');
  predicates.equalTo('titleSource', '');
  const affected: number = await requireStore().update(bucket, predicates);
  return affected > 0;
}

// 按 id 查标题来源（2026-09-05 v17）：生成链两道守卫共用——触发前守卫（'' 才生成）+
// 写回前重查（manual = 放弃）；行不存在回 'manual' 同语义（无行无生成，防幻觉写回）
export async function queryConversationTitleSource(conversationId: string): Promise<string> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['titleSource']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return result.getString(result.getColumnIndex('titleSource'));
    }
    return 'manual';
  } finally {
    result.close();
  }
}

// ═══ 会话级覆盖（DB v24 三列；2026-09-10 会话级覆盖层笔）═══
// 语义：会话是「覆盖层」的宿主——模型选择与联网开关在会话内被改动时，只落本会话，不改
// 助手/全局配置；助手配置恒为默认源（联网侧更是能力上限）。读取口径 = 生效值 =
// 本会话覆盖 ?? 默认源（模型：助手绑定→全局默认→首个启用；联网：助手启用清单）。
// 无行会话（新建未发送/隐私会话）没有行可落 → 覆盖只存内存（页面侧持有），首发落行时
// 随 insertMessage 一并写入（与 conversations.promptId「面板覆盖随首发落行」同款）。
// 会话级覆盖结构（三列 '' = 未覆盖）
export interface ConversationOverride {
  modelProviderId: string;
  modelId: string;
  webSearchOverride: string;
}

// 查会话级覆盖（三态与 queryConversationAssistantId 同口径：null = 行不存在〔无行会话〕
// → 调用方用内存覆盖；行在 = 按列值，'' = 未覆盖）
export async function queryConversationOverride(
  conversationId: string): Promise<ConversationOverride | null> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates,
    ['modelProviderId', 'modelId', 'webSearchOverride']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return {
        modelProviderId: result.getString(result.getColumnIndex('modelProviderId')),
        modelId: result.getString(result.getColumnIndex('modelId')),
        webSearchOverride: result.getString(result.getColumnIndex('webSearchOverride'))
      } as ConversationOverride;
    }
    return null;
  } finally {
    result.close();
  }
}

// 写会话级模型覆盖（providerId/modelId 传 '' = 清覆盖回默认源）。★ 无行会话命中 0 行
// **不抛错**（与 updateAssistantTools 的 0 行抛错语义不同：那里 0 行 = 目标助手被删，
// 属异常；这里 0 行 = 会话还没落行，属正常）——返回受影响行数供调用方记账
export async function updateConversationModelOverride(conversationId: string,
  providerId: string, modelId: string): Promise<number> {
  const bucket: relationalStore.ValuesBucket = { 'modelProviderId': providerId, 'modelId': modelId };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  return await requireStore().update(bucket, predicates);
}

// 写会话级联网覆盖（value '' = 跟随助手 / '0' = 本会话关闭；0 行语义同上）
export async function updateConversationWebSearchOverride(conversationId: string,
  value: string): Promise<number> {
  const bucket: relationalStore.ValuesBucket = { 'webSearchOverride': value };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  return await requireStore().update(bucket, predicates);
}

// 级联清会话级模型覆盖（删模型/删服务商时调用；providerId 必填、modelId '' = 该服务商
// 全部模型）。清列而非删行——会话与历史消息不陪葬，落回默认源即可。返回清掉的会话行数
export async function clearConversationModelOverride(providerId: string,
  modelId: string): Promise<number> {
  const bucket: relationalStore.ValuesBucket = { 'modelProviderId': '', 'modelId': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('modelProviderId', providerId);
  if (modelId !== '') {
    predicates.equalTo('modelId', modelId);
  }
  return await requireStore().update(bucket, predicates);
}

// 单独选择某模型的会话数（2026-09-17 服务商模型卡菜单与删除笔：删除前使用检测的③面；
// modelProviderId/modelId 两列双条件下 COUNT——严格对，与 clearConversationModelOverride
// 同判据；bindArgs 走 ? 占位防注入，modelId 是用户可填文本）。空对回 0（未配置语义）
export async function countConversationsByModel(providerId: string,
  modelId: string): Promise<number> {
  if (providerId === '' || modelId === '') {
    return 0;
  }
  const result: relationalStore.ResultSet = await requireStore().querySql(
    'SELECT COUNT(*) AS n FROM conversations WHERE modelProviderId = ? AND modelId = ?',
    [providerId, modelId]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('n'));
    }
    return 0;
  } finally {
    result.close();
  }
}

// 按 id 查会话加密标记（2026-09-08 记忆域沉淀链守卫——queryConversationTitleSource 同形制）：
// 加密会话不沉淀（内容蒸馏成记忆会在普通会话被注入 = 越权泄漏，任务书 §2.6）；行不存在
// 回 false（空会话退出无行 = 无沉淀面，语义自洽）
export async function queryConversationLocked(conversationId: string): Promise<boolean> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['locked']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('locked')) === 1;
    }
    return false;
  } finally {
    result.close();
  }
}

// ── 会话推荐问题列（DB v34，2026-09-19 推荐问题功能）──
// 语义（ChatDbMigrate v34 注释）：消息后追问推荐 JSON 数组串存会话行，'' = 无；会话级
// **末条覆盖写**（显示面只有末条助手消息），发送即清空写 ''，退出重进回放显示不重新生成。
// 解析/序列化单一落点 = common/SuggestGen.ets parseSuggestions/serializeSuggestions，
// 本层只存取原串。写值**不动 updatedAt**（建议写回不改变列表时间序，setConversationTitle
// 同口径）；消费方 = SuggestGen 写回/清空 + ChatPageLoad 回放装配 + 生成链重复触发守卫

// 写会话推荐问题（覆盖写，value '' = 清空）
export async function setConversationSuggestions(id: string, suggestions: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'suggestions': suggestions };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 按 id 查会话推荐问题原串（'' = 无；行不存在同回 ''——无行无建议，无生成守卫面）
export async function queryConversationSuggestions(conversationId: string): Promise<string> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['suggestions']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return result.getString(result.getColumnIndex('suggestions'));
    }
    return '';
  } finally {
    result.close();
  }
}

// 按消息集查附件行（2026-09-15 预览第三轮）：句柄委托入口——加载链（ChatPageLoad）经
// 本函数消费，不直接触达 AttachmentDb（依赖方向红线：ChatDb → AttachmentDb 单向）。
// 空集短路与 ORDER BY rowid 在 AttachmentDb 同名实现内；查询失败上抛由调用方留痕
export async function queryAttachmentsForMessages(
  messageIds: string[]): Promise<MessageAttachmentRow[]> {
  return queryAttachmentRowsForMessages(requireStore(), messageIds);
}

// ── 附件管理列表面委托（2026-09-15 附件管理列表笔）：页面侧一律经本组入口消费（依赖方向
// 红线同上；分页/空集短路/投影口径全在 AttachmentDb 同名实现内，本层只补句柄）──
// 一级按会话聚合分页（体积倒序）、二级按会话列行分页（不取 parsedText）、全局合计
export async function queryAttachmentGroups(limit: number,
  offset: number): Promise<AttachmentGroupRow[]> {
  return queryAttachmentGroupRows(requireStore(), limit, offset);
}

export async function queryAttachmentsByConversation(conversationId: string, limit: number,
  offset: number): Promise<AttachmentListRow[]> {
  return queryAttachmentRowsByConversation(requireStore(), conversationId, limit, offset);
}

export async function queryAttachmentTotal(): Promise<AttachmentTotalRow> {
  return queryAttachmentTotalRow(requireStore());
}

// 按会话附件计数（2026-09-19 会话统计半模态笔，面板「附件数」行——委托形态同上三口）
export async function queryAttachmentCount(conversationId: string): Promise<number> {
  return countAttachmentsByConversation(requireStore(), conversationId);
}

// 按附件行 id 单件删（行 + 文件成对铁律）：两段式同 deleteConversations——先删行并取回
// localPath 集，再删文件（best-effort，失败留启动收敛自愈）。附件管理页单件删走本入口，
// 页面侧不碰文件原语（否则「行删文件留」会被启动收敛的孤儿清零反噬成语义打架）。
// ★ 入参是附件行 id 不是 messageId：一条消息可挂多件附件，按 messageId 删会误伤同消息
// 其余件（任务书 §2.3 原写 deleteAttachmentsForMessages([messageId])，执行时按单件语义更正）
export async function deleteAttachments(attachmentIds: string[]): Promise<void> {
  const attachPaths: string[] = await deleteAttachmentsByIds(requireStore(), attachmentIds);
  removeAttachmentFiles(attachPaths);
}

// 插入消息（发送时 user/assistant 两条同行入库；assistant 初始 streaming 态空内容）。
// 懒创建（2026-08-29「空会话不进历史」）：入库前确保会话行存在——首条消息触发落行
//（ensureConversation），后续消息查询即返零开销。assistantId = 会话归属助手（2026-09-01
// 会话绑定；仅首条建行时消费，缺省 '' = 未绑定归默认助手口径）；promptId = 会话提示词
// 引用（2026-09-04 无行会话选提示词的内存覆盖随首发落行，仅建行时消费，缺省 ''）；
// attachments = 附件元数据行（2026-09-09 附件落盘第一轮：仅 user 行调用方随带——
// 行构建纯函数 buildAttachmentRows；assistant 行/工具行恒缺省空数组零开销）；
// override = 会话级覆盖（2026-09-10 会话级覆盖层笔：无行期在会话内改过模型/联网开关的
// 内存覆盖，随首发落行一并写入；仅建行时消费，缺省 null = 无覆盖三列全 ''）。
// ★ seq（2026-09-21 消息存储机制改造笔 2）：row.seq 有值才写本列（D4 条件键）——产品写入点
// 一律在构造行对象时经 MessageSeqDb.nextRowSeq 铸造（D1 红线禁 DB 侧赋值与 await 后补铸）
export async function insertMessage(row: MessageRow, assistantId: string = '',
  promptId: string = '', attachments: MessageAttachmentRow[] = [],
  override: ConversationOverride | null = null): Promise<void> {
  // 待落行加密标记消费（2026-09-05 会话页新建加密会话链）：id 匹配则本行 locked=1，
  // 消费即清键（防残留；id 全局唯一不复用，未消费残留本就无害——见键注释）
  let pendingLocked: boolean = false;
  const pendingId: string = AppStorage.get<string>(PENDING_LOCKED_CONV_KEY) ?? '';
  if (pendingId !== '' && pendingId === row.conversationId) {
    pendingLocked = true;
    AppStorage.setOrCreate<string>(PENDING_LOCKED_CONV_KEY, '');
  }
  await ensureConversation(row.conversationId, assistantId, promptId, pendingLocked, override);
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id,
    'conversationId': row.conversationId,
    'role': row.role,
    'content': row.content,
    'reasoning': row.reasoning,
    'status': row.status,
    'createdAt': row.createdAt
  };
  // seq 条件键（2026-09-21 消息存储机制改造笔 2 D4）：**有值才写列**——undefined 落 NULL
  //（防御性兜底：域外调用点或将来新增写点漏铸时不让整条 INSERT 失败，由启动补号 sweep 兜底）；
  // 产品写入点一律必铸（七处逐点钉在 assert-store-consistency 144 组），本键不是给调用点留的口子
  if (row.seq !== undefined) {
    bucket['seq'] = row.seq;
  }
  await requireStore().insert('messages', bucket);
  // 附件行随消息落库（2026-09-09 附件落盘第一轮）：写失败 hilog 留痕不阻断——消息已
  // 落库，附件文件转孤儿由启动收敛清理（与改造前「无元数据」等价，零回归）
  if (attachments.length > 0) {
    try {
      await insertAttachments(requireStore(), attachments);
    } catch (e) {
      const biz = e as BusinessError;
      hilog.error(DOMAIN, TAG, '附件行落库失败（文件转孤儿由启动收敛清理）：code %{public}d %{public}s',
        typeof biz.code === 'number' ? biz.code : -1, (e as Error).message);
    }
  }
  await touchConversation(row.conversationId, row.createdAt);
}

// 流式收尾一次性落库（任务书：禁逐帧写库）——完成/停止/出错三路统一走这里
export async function finalizeMessage(id: string, content: string, reasoning: string,
  status: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'content': content,
    'reasoning': reasoning,
    'status': status
  };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 重试时间推进（2026-09-20 会话统计时间跨度修复笔·七百九十六节）：重试 = 既有回答行被
// **重新生成**，该行 createdAt 随本次重试时刻前进（与 insertMessage「行时间 = 本轮发起时刻」
// 同口径），所属会话 conversations.updatedAt 同步推进（会话列表时间与排序随活跃前进）。
// 缺它的后果 = 会话统计面板「最后活跃 / 时间跨度」（= messages.createdAt 对 user/assistant
// 行的 MAX/MIN）与会话列表时间双双停在**首次生成**的时刻——真机报障「重试的消息一直跟随
// 第一次的时间」。工具轮形态（新承载行经 insertMessage）天然走到这一步，本函数补无工具轮
// 形态「就地重答」的缺。at 传 nextRowCreatedAt()（单调分配器：重试行恒为会话末条，推进后
// 仍严格晚于其余行——回放序不变；启动并列修复清扫只增不减，本值不被回改）。行不在库
//（0 行）不报错——重试行缺失本就走降级链；两表各一条 UPDATE。
// ★ 2026-09-21 消息存储机制改造笔 2（D6）：seq 与 createdAt **成对推进**——笔 3 读取切 seq 后
// 只推时间戳 = 重试消息不再置尾 = 用户可见行为破坏点（详见函数内注释）
export async function advanceRetryTimestamps(conversationId: string, msgId: string,
  at: number): Promise<void> {
  // 成对推进（D6）：新号 = 会话 max+1（走同一个铸造口，与其余铸造点同源）；铸造在首次 await
  // **之前**（D1 红线：禁 await 后补铸）。本函数只推一行（谓词 equalTo('id', msgId)）⇒ 一次
  // 调用恰一个号；号只增 ⇒ 推进后该行恒为会话内号最大者，与 createdAt 推进同向
  const seq: number = nextRowSeq(conversationId);
  const msgPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  msgPredicates.equalTo('id', msgId);
  await requireStore().update({ 'createdAt': at, 'seq': seq }, msgPredicates);
  await touchConversation(conversationId, at);
}

// 按 id 批删消息（2026-09-15 重试尾巴缝修复笔新增、同日撤链退役、2026-09-20 重试真链
// 复活取回）：重试开始清理「停止于工具执行窗口」残留的工具卡 DB 行——只清内存视图会让
// 旧卡在重进会话时复现于新答案下方。事务内级联删附件行（级联铁律同 deleteConversations：
// 任何「删 messages」路径必须同事务删附件行——本函数的删集是工具卡行，理论无附件，级联
// 为铁律兜底）；文件 I/O 在 commit 后（回滚不得已删文件红线）。返回删除行数；空集 0
export async function deleteMessagesBy(ids: string[]): Promise<number> {
  if (ids.length === 0) {
    return 0;
  }
  // 普通数组拷贝（坑6）：入参可能来自观察代理数组，直传 in() 抛 401
  const plainIds: string[] = [];
  for (const id of ids) {
    plainIds.push(id);
  }
  const db: relationalStore.RdbStore = requireStore();
  const msgPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  msgPredicates.in('id', plainIds);
  db.beginTransaction();
  try {
    const attachPaths: string[] = await deleteAttachmentsForMessages(db, plainIds);
    const deleted: number = await db.delete(msgPredicates);
    db.commit();
    removeAttachmentFiles(attachPaths); // best-effort：失败留启动收敛自愈
    return deleted;
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

// 启动恢复：残留 streaming → error
async function markStreamingAsError(): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'status': 'error' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('messages');
  predicates.equalTo('status', 'streaming');
  await requireStore().update(bucket, predicates);
}

// 时序修复行（repairTiedMessageTimestamps 内部行形态；role 参与组内角色优先序判据）
export interface RepairRow {
  id: string;
  role: string;
  createdAt: number;
  rowid: number;
}

// 重赋产物行（同上）：assigned = 重赋后新值；数组序 = 重赋后会话内顺序（调用方逐行按 id
// 写库，与遍历序无关——顺序只供真值表断言与排查读）
export interface RepairedRow {
  id: string;
  role: string;
  createdAt: number;
  rowid: number;
  assigned: number;
}

// 并列组重赋纯函数（直跑断言面 = assert-store-consistency 117 组真值表；入参行序 =
// createdAt ASC, rowid ASC，由调用方 SQL 保证）：同一 createdAt 为一组，组内按角色优先序
//（user < tool < assistant，同角色按 rowid）重排后自基线连续赋值 base + i；基线 =
// max(组原值, 前行新值 + 1)（前组占用推后组基线，级联安全）。契约三条：
// · 组内序取角色语义、不取物理插入序——并列组实际形态恒为「工具行 + 紧随的下一轮
//   assistant 占位行」（工具先于回复），而物理插入序不可控：insertMessage 先 await
//   ensureConversation 查询再插、完成序掷硬币（2026-09-19 根因原文，变更记录七百八十一节）；
// · 只治并列——单行组仅在前组占用推基线时才实际改值（健康会话零扰动；重赋后组内值互异且
//   全序严格递增 ⇒ 候选门不再命中，重跑零更新幂等）；
// · 只增不减——新值恒 ≥ 原值（重试推进值/统计/翻页游标语义只向后平移）。
// ★ 2026-09-21 回退（本函数替代 2026-09-20 的 computeCausalCreatedAt）：D4-1 曾改「读行序 =
// 物理插入序整体重赋 + 候选门放宽为 rowid 序非严格递增」，前提「物理插入序即因果序」正是
// 09-19 根因否掉的那枚硬币 ⇒ 会把角色序已修正的存量会话按物理倒挂改回去（真机复现「重进后
// 工具卡出现在最新消息后」，且改写后自洽固化、不再进候选）；真机故障与判定见 2026-09-21
// 八百四十四节（★ 2026-09-21 复核轮核正：原写「八百四十三节」是邻节误引——843 为 StoragePage
// toast 笔，本笔号才是 844）
export function computeTieRepairedRows(rows: RepairRow[]): RepairedRow[] {
  const out: RepairedRow[] = [];
  const roleRank = (role: string): number =>
    role === 'user' ? 0 : (role === 'tool' ? 1 : 2);
  let index: number = 0;
  let prevAssigned: number = 0;
  while (index < rows.length) {
    let end: number = index;
    while (end < rows.length && rows[end].createdAt === rows[index].createdAt) {
      end++;
    }
    const base: number = rows[index].createdAt > prevAssigned
      ? rows[index].createdAt : prevAssigned + 1;
    const group: RepairRow[] = rows.slice(index, end);
    group.sort((a: RepairRow, b: RepairRow): number =>
      roleRank(a.role) - roleRank(b.role) || a.rowid - b.rowid);
    for (let i: number = 0; i < group.length; i++) {
      prevAssigned = base + i;
      out.push({
        id: group[i].id, role: group[i].role, createdAt: group[i].createdAt,
        rowid: group[i].rowid, assigned: prevAssigned
      });
    }
    index = end;
  }
  return out;
}

// 同毫秒并列修复清扫（2026-09-19 工具卡回放乱序修复笔；★ 2026-09-21 回退至本形态，见
// computeTieRepairedRows 回退说明）：启动幂等数据维护（sweepEmptyConversations 先例，非
// 版本迁移）。历史落库笔在「工具行与下一轮 assistant 占位行」同一同步链取 Date.now()，
// 同毫秒并列组重进回放序取决于物理插入序（真机实锤工具卡跑到最新消息后）。修复 = 逐候选
// 会话按 createdAt 分组、组内角色优先序重排后连续重赋（computeTieRepairedRows 三条契约），
// 修复后会话内 createdAt 严格递增，重跑零更新（幂等）。只动 createdAt 列，内容零触碰；
// 统计/翻页游标/备份随值自然一致；导入旧备份若再引入并列，下次启动本清扫自愈。事务包裹
//（P0-1 不半修）
// ★ 候选门 = 同毫秒并列（2026-09-21 回退口径）：只看时间戳有无并列组，不猜物理插入序。
// 并列之外「时间戳互异但物理序倒挂」的会话一律不碰——时间戳序即显示序（写入侧单调分配器
// 保证新数据因果递增），此类会话显示本就正确，按物理序改写反而制造倒挂（D4-1 真机故障面 =
// 候选门放宽「rowid 序非严格递增」+ 行序改物理插入序，两处前提都是那枚不可控的硬币）
async function repairTiedMessageTimestamps(): Promise<void> {
  const db: relationalStore.RdbStore = requireStore();
  const grpResult: relationalStore.ResultSet = await db.querySql(
    'SELECT conversationId FROM messages GROUP BY conversationId, createdAt HAVING COUNT(*) > 1');
  const convIds: string[] = [];
  try {
    while (grpResult.goToNextRow()) {
      const convId: string = grpResult.getString(grpResult.getColumnIndex('conversationId'));
      if (!convIds.includes(convId)) {
        convIds.push(convId);
      }
    }
  } finally {
    grpResult.close();
  }
  if (convIds.length === 0) {
    return; // 稳态零成本（绝大多数启动走此出口）
  }
  let repaired: number = 0;
  db.beginTransaction();
  try {
    for (const convId of convIds) {
      // 行序 = createdAt ASC, rowid ASC（时间戳定组序、rowid 只做组内同角色决胜——重赋依赖
      // 此行序；禁改物理序，那等于把「物理插入序」重新扶成因果真源，见上回退说明）
      const rowResult: relationalStore.ResultSet = await db.querySql(
        'SELECT id, role, createdAt, rowid FROM messages WHERE conversationId = ? ' +
        'ORDER BY createdAt ASC, rowid ASC', [convId]);
      const rows: RepairRow[] = [];
      try {
        while (rowResult.goToNextRow()) {
          rows.push({
            id: rowResult.getString(rowResult.getColumnIndex('id')),
            role: rowResult.getString(rowResult.getColumnIndex('role')),
            createdAt: rowResult.getLong(rowResult.getColumnIndex('createdAt')),
            rowid: rowResult.getLong(rowResult.getColumnIndex('rowid'))
          });
        }
      } finally {
        rowResult.close();
      }
      // 并列组重赋（纯函数）+ 逐行比对落 UPDATE（值未变不写——幂等、事务内最少写）。
      // ★ 写定位键 = rowid（2026-09-22 自检轮收口 856 登记的「同类隐患」）：本函数候选门是
      // **值判据**（`GROUP BY conversationId, createdAt HAVING COUNT(*) > 1`）⇒ 它必须能改写
      // 命中会话里的**任何**一行；而 `id` 可为 NULL（SQLite 的 TEXT PRIMARY KEY 不拒 NULL，
      // 官方明载——见 ChatDbMigrate v37 注释），`WHERE id = ?` 对这类行恒零行命中 ⇒ 并列永不
      // 修复、候选门每次启动重新命中（幂等契约破）+ 计数虚增。rowid 恒非 NULL 恒唯一 ⇒ 任何行
      // 都可定位，与 MessageSeqDb.backfillMessageSeq 同一条不变式（同族两处同修）
      const repairedRows: RepairedRow[] = computeTieRepairedRows(rows);
      for (let i: number = 0; i < repairedRows.length; i++) {
        if (repairedRows[i].assigned !== repairedRows[i].createdAt) {
          await db.executeSql('UPDATE messages SET createdAt = ? WHERE rowid = ?',
            [repairedRows[i].assigned, repairedRows[i].rowid]);
          repaired++;
        }
      }
    }
    db.commit();
    hilog.info(DOMAIN, TAG, '并列修复清扫：%{public}d 个候选会话，重赋 %{public}d 行',
      convIds.length, repaired);
  } catch (e) {
    db.rollBack();
    throw e as Error;
  }
}

async function touchConversation(conversationId: string, at: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'updatedAt': at };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  await requireStore().update(bucket, predicates);
}
