// 聊天存储层：relationalStore（官方 SQLite），库 aicontrol.db 单一初始化源。
// 表结构 v66（版本史/建表 SQL/迁移细则单一来源 = ChatDbMigrate.ets 头注释；版本号走
// store.version，两铁律「逐级 + 幂等」同在彼处）。表清单与行读写所属域件：conversations +
// messages（v46 起含图节点身份五列）+ providers / provider_models / provider_keys（★key
// 明文禁落 DB——表只存元数据，明文在 Asset，见 KeyStore）+ token_usage_events /
// message_attachments / prompt_templates / assistants / memories + assistant_memories /
// price_templates / http_templates（行读写分属 UsageStatsDb / AttachmentDb /
// PromptTemplateDb / AssistantDb / MemoryDb / PriceTemplateDb / HttpTemplateDb）+
// workspace_files（跨会话持久资产——删会话删助手零级联、不进导出清单；WorkspaceDb 家族）+
// folder_mounts（授权 AI 访问本机文件夹的记录，不进导出清单；MountDb）+ skills /
// skill_files（SkillDb）+ knowledge_books / knowledge_entries / knowledge_files 三表
// （KnowledgeDb，纯函数 KnowledgeText.ets）+
// memory_snapshots（不进导出清单；MemoryDb）+ branches / generation_runs / tool_facts /
// summary_bindings / attachment_refs / graph_capability（图侧六表——分支图身份与命令层单源
// MessageBranchDb.ets；旧库迁移器已删，新建会话出生即图态）+ send_queue_items /
// send_queue_state（单源 ChatSendQueueDb.ets；不进导出清单——排队是发送意图非资产事实）+
// mcp_servers（单源 McpDb.ets、头值明文走 Asset〔KeyStore 第九形态〕；★进导出清单——用户
// 搭建资产随备份走，头值明文恒不随）。
// 跨会话读/检索域已拆 ChatDbReadSearch.ets（依赖单向 = 彼件 import 本件，本件不反引零环）；
// 写侧、单会话读写、生命周期、格式态路由与全部委托族在本文件。
// 红线：①DB 在沙箱；②初始化异步（EntryAbility 发起，UI 经 whenReady() 等待，未就绪禁发送）；
// ③流式增量经 250ms latest-wins checkpoint 落库（流中占位行 streaming，完成/停止/出错同事务
// 收口 done；工具轮中间行走 settleRoundAssistant 同拍收口）；④消息查询一律 LIMIT（会话列表
// 全量 = 本条例外——决明拍板，行轻有界，见 queryConversations）；⑤启动清算分流（图态
// streaming 占位行由 sweepStaleGraphRuns 接管，非图态残行改 error 兜底）；⑥ResultSet 用完
// close（官方要求）。
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { ensureSchema, migrateSchema, verifyDbOpenable } from './ChatDbMigrate';
import { runWriteQueued } from './DbWriteQueue';
import { markStreamingAsError, repairTiedMessageTimestamps,
  sweepEmptyConversations, sweepStaleGraphRuns } from './ChatDbSweep';
// ★ 图域依赖方向（坑50 零环红线）：本件禁 import MessageBranchDb——双向边会让 ArkTS 类型
// 检查器在环上崩坏（实测实锤）。图命令编排全走 ChatContextSource（单向 import 本件与彼件）
import { backfillMessageSeq, nextRowSeq, seedMessageSeq } from './MessageSeqDb';
import { countAttachmentsByConversation, deleteAttachmentsByIds,
  deleteAttachmentsForConversations, deleteAttachmentsByCutoff as deleteAttachmentsByCutoffRow,
  AttachmentGroupRow, AttachmentListRow, AttachmentTotalRow, MessageAttachmentRow,
  queryAttachmentGroups as queryAttachmentGroupRows,
  queryAttachmentTotal as queryAttachmentTotalRow,
  queryAttachmentsByConversation as queryAttachmentRowsByConversation,
  queryAttachmentsForMessages as queryAttachmentRowsForMessages,
  readAttachmentCleanPreview as readAttachmentCleanPreviewRow,
  removeAttachmentFiles } from './AttachmentDb';
// 工作区存储域：依赖方向本件 → WorkspaceDb → WorkspaceUtil 单向（WorkspaceDb 不 import
// 本件，句柄由委托层传入）
import { WorkspaceFileRow, WORKSPACE_SOURCE_ASSISTANT } from '../WorkspaceUtil';
import { WorkspaceSaveOutcome,
  WorkspaceTotalRow,
  ensureWorkspaceDirRows,
  mountCopyIntoWorkspace,
  queryWorkspaceFiles as queryWorkspaceFileRows,
  queryWorkspaceFilesByName as queryWorkspaceFileRowsByName,
  queryWorkspaceTotal as queryWorkspaceTotalRowOf,
  saveWorkspaceTextFile, upsertWorkspaceRow,
  deleteWorkspaceRowsByIds } from './WorkspaceDb';
// 目录四操作域外迁拆分件 WorkspaceDbEntries（本件仍为唯一委托层，执行器不直碰 store）
import { WorkspaceEntryOpOutcome, createWorkspaceDir, deleteWorkspaceEntry,
  moveWorkspaceEntry, renameWorkspaceEntry } from './WorkspaceDbEntries';
// 管理页三口入链编排拆分件 WorkspaceDbManage
import { clearWorkspaceAllQueued, deleteWorkspaceFilesQueued,
  insertWorkspaceFileQueued } from './WorkspaceDbManage';
// 识别文字存储拆分件 WorkspaceDbOcr（六列读写全在彼件，本层只补句柄）
import { WorkspaceOcrRecord, queryWorkspaceOcr as queryWorkspaceOcrOf,
  queryWorkspaceOcrHasText as queryWorkspaceOcrHasTextOf,
  queryWorkspaceFileRowById as queryWorkspaceFileRowByIdOf,
  saveWorkspaceOcrQueued as saveWorkspaceOcrQueuedOf,
  saveWorkspaceOcrEditQueued as saveWorkspaceOcrEditQueuedOf } from './WorkspaceDbOcr';
import { saveWorkspaceXlsxFile } from './WorkspaceDbXlsx';
// 目录排序域拆分件 WorkspaceDbDirOrder（委托口直引拆分件，实现与入链/事务全在彼件）
import { saveWorkspaceDirOrder as saveWorkspaceDirOrderOf } from './WorkspaceDbDirOrder';
// 编辑编排拆分件 WorkspaceDbEdit（照 WorkspaceDbXlsx 先例）
import { editWorkspaceTextFile, WorkspaceEditOutcome } from './WorkspaceDbEdit';
// 文件夹挂载存储域件 MountDb（依赖方向本件 → MountDb 单向无环，委托口在本文件）
import { FolderMountRow, deleteFolderMountRow, insertFolderMountRow,
  queryFolderMountRows, updateFolderMountGrant as updateFolderMountGrantRow,
  updateFolderMountName } from './MountDb';
// MCP 服务器存储域件 McpDb（照 MountDb 拆分先例——依赖方向本件 → McpDb 单向无环，
// 委托口在本文件，行读写与入链全在彼件）
import { McpServerRow, deleteMcpServerCascade, insertMcpServer,
  queryMcpServers as queryMcpServerRows,
  updateMcpServer as updateMcpServerRow, updateMcpServerEnabled as updateMcpServerEnabledRow,
  updateMcpServerTools as updateMcpServerToolsRow } from './McpDb';
// 头值 Asset 存取（KeyStore 第九形态——纯叶子件添边无环）与元数据解析（McpText 纯函数
// 叶子）。「先 Asset 后 DB」写序与删除级联的组清理编排收口在本文件委托层单点
import { loadMcpHeaderValues, removeMcpHeaderValues, saveMcpHeaderValues } from './KeyStore';
import { parseMcpHeaderMeta } from '../McpText';
// 临时产物区存储件 WorkspaceDbTmp（依赖本件 → WorkspaceDbTmp → WorkspaceDb 单向无环；
// 级联收编 + 委托口在本文件，扫描/删除/转存实现全在彼件）
import { collectTmpForConversations, deleteWorkspaceTmpConversationsQuiet,
  deleteWorkspaceTmpConversation as deleteWorkspaceTmpConversationOf,
  deleteWorkspaceTmpFile as deleteWorkspaceTmpFileOf,
  clearWorkspaceTmpAll as clearWorkspaceTmpAllOf,
  listWorkspaceTmpFiles as listWorkspaceTmpFilesOf,
  listWorkspaceTmpGroups as listWorkspaceTmpGroupsOf,
  countWorkspaceTmpFiles as countWorkspaceTmpFilesOf,
  workspaceTmpTotalBytes as workspaceTmpTotalBytesOf,
  promoteWorkspaceTmpFile as promoteWorkspaceTmpFileOf,
  scanWorkspaceTmpOverview as scanWorkspaceTmpOverviewOf,
  PromoteOutcome } from './WorkspaceDbTmp';
// Python 会话命名空间释放（门 4：删除会话级联 best-effort 调用；实现在 pyexec 域）
import { dropPyNamespacesQuiet } from '../pyexec/PyRuntime';
// Node 会话 worker 释放（门 2：删除会话级联 best-effort 调用；实现在 nodeexec 域，单向
// store → nodeexec → bridge/runtime，无回边）
import { dropNodeForConversation } from '../nodeexec/NodeScheduler';
import { WorkspaceTmpGroupBrief, WorkspaceTmpScan } from '../WorkspaceTmpUtil';
// 数据总览载荷类型（UI 与委托层同源引用）
import { WorkspaceDataStats } from '../WorkspaceStatsUtil';

const DOMAIN: number = 0x0001;
const TAG: string = 'ChatDb';
const DB_NAME: string = 'aicontrol.db';
// 会话 id 兜底值（ChatPage 结构缺省——正常链路 id 均由 push/replace 注入；该 id 无预建行，
// 发送时经 ensureConversation 懒建，「空会话不进历史」语义统一管辖）
export const DEFAULT_CONVERSATION_ID: string = 'conv-default';
// 消息查询上限（首次拉尾部 50 条）
export const QUERY_TAIL_LIMIT: number = 50;

export interface ConversationRow {
  id: string;
  title: string;
  providerId: string;
  createdAt: number;
  updatedAt: number;
  // 标题来源三态（v17）：'' = 占位（首条升级为截断占位，AI 回复后触发生成）/ 'ai' = AI 已
  // 生成 / 'manual' = 用户手改（生成链两道守卫见此即放弃）——语义见 TitleGen.ets
  titleSource: string;
  // 收藏标记（v19）：true = 收藏（星标 + 分段过滤）；只改标记列不动 updatedAt——语义见
  // ChatDbMigrate v19 注释
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
  // 行物理序：查询投影带回、插入路径不带（rowid 库自派）。seq 切序后读取面消费面归零
  //（原消费面 = 翻页游标决胜键 MessageCursor），列仍随显式投影带回、机制不退役（D5）
  rowid?: number;
  // ── 多版本（v36，仅 assistant 行有意义）：'' / 缺省 = 单版消息（从未重试）；variants 为
  // 全量真源 JSON 串（结构与读写口单源 = MessageVariantDb.ets），content 列恒存选中版内容
  //（现役读方零改动的关键），variantActive = 选中下标；查询投影带回、插入路径不带
  variants?: string;
  variantActive?: number;
  // ── 会话内显式序号（v37）：由写入侧分配器铸造（MessageSeqDb.nextRowSeq，会话内 0 基
  // 递增；D1 红线见该域件头注释）。可选 = 防御性兜底（undefined ⇒ insertMessage 不写本列、
  // 落 NULL，由启动补号与导入补号兜底）；产品写入点一律必铸（七处逐点钉在
  // assert-store-consistency 144 组）。查询投影带回 + 排序权威（单会话读窗口与翻页游标切
  // seq；跨会话检索窗禁切——判据见 searchMessagesAcross 注释）
  seq?: number;
  // ── 压缩摘要覆盖边界（v42，仅 summary 行有意义——组装裁段判据，写入唯一点 CompressDb）
  coversToSeq?: number;
  // ── 引用全文快照（v61，仅 user 行有意义）：缺省落 NULL（NULL = 从未有引用，'' 不出现
  //——仿 seq 兜底口径）。写走 prepareRun bucket 条件写键（MessageBranchDb，不走
  // insertMessage——legacy 写口已删）；读走读窗 IN 投影（ChatContextSource.adaptPathRows）
  //。content 列恒存用户原文，引用前缀只在组装层拼装
  quoteText?: string;
  // ── DeepSeek 服务端工具原样 JSON 串（v64，仅 assistant 行有意义——DS 全家桶接入批 S2）：
  // {"server_tool_calls":…,"annotations":…} 官方末帧两字段合体，回传保真禁截断禁重排
  //（signature 超限被腰斩 = 回传 400，任务书 §5）。缺省落 NULL（NULL = 非官方档轮/无服务端
  // 步骤，'' 不出现——与 quoteText 同款空串/NULL 语义分家）。写走轮收口条件写键
  //（MessageBranchDb.writeNodeServerTools——终答/中间轮提交口两调用点）；读走行投影
  //（chatMessagesFromRows → ChatMessage.serverToolsJson）→ 请求回传
  //（buildRequestHistory → composeOpenAiBody server_tool_calls 仅官方档轮输出）
  serverTools?: string;
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
  // v15 能力派生/覆盖标志——false = 未手改，caps 走 effectiveCaps 读时按模型名派生
  //（ModelRegistry，派生值不落库）；true = 用户手改固化，caps 原样生效（含显式全不勾）
  capsUserModified: boolean;
  // v21 模型收藏标记：随模型行同生命周期（删模型/删服务商/取消勾选即随行清除）；本机
  // 语义，分享不携带（语义见 ChatDbMigrate v21 注释）
  favorite: boolean;
  // v27 价格 JSON 串（'' = 未配置；元/百万 tokens）。结构单一来源 = CostStatsCalc.ets
  //（parsePriceConfig / serializePriceConfig）——本注释不复制结构防双源
  priceConfig: string;
  // v33 上下文窗口 token 数：0 = 未配置 = 跟随内置参考值（ModelRegistry 读时派生不落库）；
  // 非 0 = 用户覆盖（与 caps 派生/覆盖家族同构）。★ 本列无消费面：历史裁剪/用量占比/
  // 请求组装/费用估计一律不读
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

// 消息行 createdAt 单调分配器（坑：工具卡回放乱序——同毫秒并列后重进回放序取决于物理
// 插入序）。契约 = 同进程内每次调用严格大于上一次（撞毫秒 +1 让位），行间逻辑先后完全由
// 调用序表达。接入点 = 全部产品消息写入点；残留同毫秒（跨进程/旧数据）由启动幂等修复
// 清扫兜底（repairTiedMessageTimestamps）。显示序权威已归 seq，本分配器消费面收窄为
// 时间显示与修复器取值
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
    // 双层降级守卫（版本闸 + 图能力闸，实现 = ChatDbMigrate.verifyDbOpenable）：命中即抛错
    //（catch 返假 → UI 可观察），fail-closed——不进迁移/维护、不拿句柄；必须先于
    // ensureSchema/migrateSchema
    await verifyDbOpenable(rdb);
    // 新装建表 + 版本迁移（两铁律见 ChatDbMigrate.ets 头注释）
    await ensureSchema(rdb);
    await migrateSchema(rdb);
    // ★ J11：store 赋值在全部成功之后（原在维护链前赋值，失败后 isReady() 仍真、可读半成品
    // 库）；维护链显式传 rdb 句柄，失败路径 store 保持 null
    // 旧「陈旧 migrating 复位清扫」已随迁移机制退役——migrating 残值按墓碑读，无复位对象
    // 空会话清扫（「空会话不进历史」配套）：删无任何消息的会话行——懒创建启用前的存量垃圾，
    // 此后空行不再产生，仅启动跑一次。默认会话行不预建，兜底 id 发送时经 ensureConversation 懒建
    await sweepEmptyConversations(rdb);
    // 中断恢复：上次退出残留 streaming 态改 error（不永远转圈）。图态会话排除（图态有流中
    // 占位行，一律改 error 会把半截正文显「出错」）——图态行由下方 sweepStaleGraphRuns 接管
    await markStreamingAsError(rdb);
    // 非终态 run 中断收口：残留 prepared/running run 收口终态（不重发请求、不重放未知结果）；
    // failed → **interrupted**（区分「进程死亡」与「真失败」）+ 尾部 streaming 占位行收口
    // done（半截成终答）+ 诊断 notice 挂 run.diagnosticMessageId。实现在 ChatDbSweep（不
    // import 命令层防环，写面与 MessageBranchDb.finishRun interrupted 形态逐字段对齐——互证
    // 见彼处）；graph 会话走图维护，不进并列修复/seq 补号两件 legacy 维护（已加 graph 排除）
    await sweepStaleGraphRuns(rdb);
    // 并列修复清扫（幂等启动维护，详见被调函数注释）
    await repairTiedMessageTimestamps(rdb);
    // seq 补号清扫（NULL/缺号/重号的会话整会话重算，稳态零写；实现与规则在
    // MessageSeqDb.ets）。必须在 migrateSchema 之后（先建列再回填）；句柄传 rdb（域件不
    // import 本件，零环）
    await backfillMessageSeq(rdb);
    // seq 分配器播种：写入侧分配器的进程内记账从库中真值回读——必须在补号 sweep 之后
    //（sweep 先归一残缺号，播种读修复后的真值）。失败上抛 → 返假 → UI 报初始化失败（不静默）
    await seedMessageSeq(rdb);
    // 就绪发布（J11 修复后唯一赋值点）：维护链全绿才公开句柄
    store = rdb;
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

// 共享库句柄（ProviderDb 等域件消费——同一 aicontrol.db 单一初始化源；未就绪同样抛错）
export function sharedRdbStore(): relationalStore.RdbStore {
  return requireStore();
}

// 会话列表：按最近更新倒序，**全量查询**（2026-09-04 决明拍板：本地 RDB 查全量毫秒级、
// 会话行轻规模有界——删原 50 上限与滚动分页；红线④本条例外）。按 assistantId 集过滤
//（历史只显示当前助手名下；id 集由 AssistantDb.historyFilterIds 给——'' 行 = 默认助手
// 名下，仅默认助手口径含 ''）；入参纯数组（坑6 族）。全列查询凑齐 ConversationRow。
export async function queryConversations(assistantIds: string[]): Promise<ConversationRow[]> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.in('assistantId', assistantIds);
  predicates.orderByDesc('updatedAt');
  const columns: string[] = ['id', 'title', 'providerId', 'createdAt', 'updatedAt', 'titleSource',
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

// 会话收藏标记写值（菜单唯一落点）：只改标记列不动 updatedAt（不改变列表时间序）
export async function setConversationFavorite(id: string, favorite: boolean): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'favorite': favorite ? 1 : 0 };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 首条消息确保会话行存在（「空会话不进历史」）：会话行不在「新建」时预建（原
// createConversation 已删）——新建只本地生成 id 直接进对话页，首条消息 insertMessage 时才
// 落行；空会话在 DB 无行，历史列表自然不显示也无空行垃圾。标题固定「新对话」，时间序由
// touchConversation 随首条消息维护（列表置顶）。★ assistantId 与 promptId 两值同落互不
// 清零（assistantId = 有效归属实体值，恒非 ''；promptId = 面板提示词覆盖，'' = 未启用注入）
export async function ensureConversation(conversationId: string, assistantId: string,
  promptId: string = '',
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
    // 会话级覆盖随首发落行（2026-09-10 会话级覆盖层笔）：无行期改动只存内存，此处补写入行
    'modelProviderId': override !== null ? override.modelProviderId : '',
    'modelId': override !== null ? override.modelId : '',
    'webSearchOverride': override !== null ? override.webSearchOverride : ''
  };
  await requireStore().insert('conversations', bucket);
}

// Node 会话 worker 级联释放（best-effort）：会话 id 即 Node sessionId（bootstrap 每 sessionId
// 一个长期 worker，NodeScheduler 侧同样以 conversationId ↔ sessionId 一一对应）；同步段先递增
// 取消代次并撤回排队，异步段 drop 失败只留痕不回滚——会话目录与 DB 行已随本笔删除，worker
// 残留不构成用户面可见状态。空集合直接返回（无运行时开销）。
function dropNodeWorkersQuiet(conversationIds: string[]): void {
  for (const conversationId of conversationIds) {
    dropNodeForConversation(conversationId, conversationId).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'Node 会话 worker 级联删除失败（会话 %{public}s）：%{public}s',
        conversationId, (e as Error).message);
    });
  }
}

// 批量彻底删除会话：messages 与 conversations 两表建表无外键约束——「彻底删除」必须同
// 事务手动级联删（beginTransaction/commit/rollBack 三件套，任一步失败整体回滚不半删）。
// 返回删除的会话行数；空入参直接 0（无事务开销，兼防 in() 空数组「条件失效落全表」）。
// 默认会话（conv-default）行可删（空行即清），对话页兜底 id 发送时经 ensureConversation 懒建。
// ★ 级联铁律：任何新增「删 messages」路径，必须在同函数同事务内删附件行（全仓删 messages
// 落点 = 本函数 + AssistantDb.deleteAssistantCascade 两处；sse-assert ㊽ 组 tripwire 钉
// messages 谓词计数）。
// 事务内级联：token_usage_events（删会话不保留统计——决明口径④；不调 UsageStatsDb，其
// import 本文件禁循环依赖）+ message_attachments（文件本体删除在 commit 后）+ 图侧五表 +
// send_queue_items / send_queue_state（排队行随会话——删后队列已不可达，残留即孤儿行；
// 运行态内存队列随下次 hydrate / 5s 空闲回收对齐，会话已不可进无用户面危害）
export async function deleteConversations(ids: string[]): Promise<number> {
  if (ids.length === 0) {
    return 0;
  }
  const db: relationalStore.RdbStore = requireStore();
  // ★ 坑6：入参可能来自 @State（观察代理数组）——直传 in() 抛 401，逐元素拷进新建普通
  // 数组后通过；若 SDK 仍报同错，回退 = executeSql + IN 占位符 bindArgs（同需纯数组）
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
  // 写串行链入链（14800024 收口；谓词构造读段留链外；commit 后文件删除时序不变）
  return runWriteQueued('deleteConversations', async (): Promise<number> => {
    // 临时区级联收集（已过排队、事务未开纯 fs 收集；收集逻辑在 WorkspaceDbTmp——本件越
    // 1200 硬线不原位堆逻辑）
    const tmpConvIds: string[] = collectTmpForConversations(plainIds);
    db.beginTransaction();
    try {
      // 附件行级联：先 SELECT 收集 localPath 再删行；文件 I/O 在 commit 之后（回滚不得已删文件）
      const attachPaths: string[] = await deleteAttachmentsForConversations(db, plainIds);
      await db.delete(msgPredicates);
      await db.delete(usagePredicates);
      // 图侧级联（graph 会话图行随会话同删防孤儿；legacy 空删幂等零开销。删序先子后父
      //——无外键约束仍按依赖序写；K4：整会话删除 = 节点全不可达，附件行已上方全删，refs 随清）
      await db.executeSql('DELETE FROM attachment_refs WHERE conversationId IN (' +
        plainIds.map((_id: string): string => '?').join(',') + ')', plainIds);
      await db.executeSql('DELETE FROM summary_bindings WHERE conversationId IN (' +
        plainIds.map((_id: string): string => '?').join(',') + ')', plainIds);
      await db.executeSql('DELETE FROM tool_facts WHERE runId IN (SELECT id FROM ' +
        'generation_runs WHERE conversationId IN (' +
        plainIds.map((_id: string): string => '?').join(',') + '))', plainIds);
      await db.executeSql('DELETE FROM generation_runs WHERE conversationId IN (' +
        plainIds.map((_id: string): string => '?').join(',') + ')', plainIds);
      await db.executeSql('DELETE FROM branches WHERE conversationId IN (' +
        plainIds.map((_id: string): string => '?').join(',') + ')', plainIds);
      // 排队行级联（随会话，不删即孤儿行；同事务）
      await db.executeSql('DELETE FROM send_queue_items WHERE conversationId IN (' +
        plainIds.map((_id: string): string => '?').join(',') + ')', plainIds);
      // 排队运行态级联（一会话一行，生命周期同会话；同事务同域）
      await db.executeSql('DELETE FROM send_queue_state WHERE conversationId IN (' +
        plainIds.map((_id: string): string => '?').join(',') + ')', plainIds);
      const deleted: number = await db.delete(convPredicates);
      db.commit();
      removeAttachmentFiles(attachPaths); // best-effort：失败留启动收敛自愈
      // 临时区级联删除（同款两段式：commit 后 best-effort 不回滚；漏网孤儿目录管理页可见可清）
      deleteWorkspaceTmpConversationsQuiet(tmpConvIds);
      // Python 会话命名空间级联（门 4 方案 §2.4 行为矩阵「删除会话 = 删除对应命名空间引用」；
      // 实现在 pyexec 域——本件不堆逻辑；best-effort：余量由 native LRU 上限与进程重启兜底）
      dropPyNamespacesQuiet(tmpConvIds);
      // Node 会话 worker 级联（门 2 §3.3 删除矩阵）：撤回排队 + 终止在跑 + drop worker；
      // 传被删会话全集 plainIds——worker 挂在会话而非临时区，无临时区会话同样可能有 worker，
      // 无 worker 的多余 id 对被调方是无害空操作；best-effort 不阻塞删除链（运行时未启动 =
      // 无害空操作；失败由会话目录已清与进程重启兜底）
      dropNodeWorkersQuiet(plainIds);
      return deleted;
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}

// 全库会话 id 清单（清空对话记录的取数口）：只投影 id 列、无 assistantId 过滤（清空 = 跨
// 全部助手，与设置页「数据与隐私」删除承诺同域）；不做 LIMIT——截断即漏删（行轻有界，
// 同会话列表全量拍板口径），且本查询只取一列更轻。
export async function queryAllConversationIds(): Promise<string[]> {
  const rs: relationalStore.ResultSet = await requireStore().querySql('SELECT id FROM conversations');
  const ids: string[] = [];
  try {
    while (rs.goToNextRow()) {
      ids.push(rs.getString(rs.getColumnIndex('id')));
    }
  } finally {
    rs.close();
  }
  return ids;
}

// 清空会话每批条数（只约束绑定参数规模，与语义无关）：单批 deleteConversations 把 id 集
// 展开到十一处谓词/占位符 ≈ 11N 个绑定参数——N 取 50 使单批 ≈550，稳低于任何 SQLite 版本
// 的 SQLITE_MAX_VARIABLE_NUMBER 下限（999）。分批只影响事务粒度，不影响删除范围。
const CLEAR_CONV_BATCH: number = 50;

// 清空全部会话（唯一调用方 = 快速清理页）：取全量 id 后分批走既有 deleteConversations
// 级联（级联铁律不在本函数复制——删 messages 路径仍只有彼两处，本函数只是批量驱动）。
// 返回实删会话行数合计。★ 每批独立事务：某批失败即抛，此前批次已提交不回滚，剩余会话
// 原样保留（P0-1 报错不静默，不存在半删行）。不推 SESSION_LIST_RELOAD_KEY——刷新广播
// 由页面层负责（DataSyncPage 同款分工）。
export async function clearAllConversations(): Promise<number> {
  const ids: string[] = await queryAllConversationIds();
  let removed: number = 0;
  for (let i = 0; i < ids.length; i += CLEAR_CONV_BATCH) {
    removed += await deleteConversations(ids.slice(i, i + CLEAR_CONV_BATCH));
  }
  return removed;
}

// 重命名会话：仅改标题、不动 updatedAt（不改变列表时间序）；空值/同值校验在 InputDialog
// 内。v17：同条 UPDATE 内嵌 titleSource='manual'（用户手改终胜——AI 生成链写回前重查见
// manual 即放弃；同条原子落库防「title 已改 / source 未改」中间态被生成链踩）
export async function renameConversation(id: string, title: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'title': title, 'titleSource': 'manual' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 标题写回（v17）：title 与 titleSource 同条 UPDATE 原子落库、**不动 updatedAt**（同
// renameConversation 口径）。消费方 = TitleGen 两写点——AI 写回 ('ai') 与首条占位升级
//（''：title 为截断占位串，生成链照常触发）。调用方负责写回前重查守卫（manual 放弃）
// 标题来源值域（二期 #4 补 'ds'）：'' = 占位态 / 'manual' = 用户手改（终胜出，任何自动
// 链都不覆盖）/ 'auto' 系 = TitleGen 独立请求 / 'ds' = DS 官方顺带生成的标题
//（ChatDsStreamExtrasCtrl.writeTitle 写口；非空即让 TitleGen 的 source !== '' 守卫自然让位）
export async function setConversationTitle(id: string, title: string, source: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'title': title, 'titleSource': source };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  await requireStore().update(bucket, predicates);
}

// 占位标题条件升级（v17）：仅当行仍为「新对话 + 占位态''」才写截断标题——条件谓词 UPDATE
// 原子闸，天然防两类并发覆盖（①已升级行 title != '新对话' 不中；②窗口内用户已改名 =
// manual 不中）；同样不动 updatedAt。返回是否升级；executeSql 无行数返回（d.ts
// Promise<void>）故走 update 谓词式（affected 先例 = ProviderDb.updateProviderPromptCache）
export async function upgradePlaceholderTitle(id: string, title: string): Promise<boolean> {
  const bucket: relationalStore.ValuesBucket = { 'title': title, 'titleSource': '' };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', id);
  predicates.equalTo('title', '新对话');
  predicates.equalTo('titleSource', '');
  const affected: number = await requireStore().update(bucket, predicates);
  return affected > 0;
}

// 按 id 查标题来源（v17）：生成链两道守卫共用——触发前守卫（'' 才生成）+ 写回前重查
//（manual = 放弃）；行不存在回 'manual' 同语义（无行无生成，防幻觉写回）
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

// ═══ 会话级覆盖（DB v24 三列）═══
// 语义：会话是「覆盖层」宿主——模型选择与联网开关在会话内被改动时只落本会话，不改助手/
// 全局配置（助手配置恒为默认源）。生效值 = 本会话覆盖 ?? 默认源（模型：助手绑定→全局默认
//→首个启用；联网：助手启用清单）。无行会话（新建未发送/隐私会话）→ 覆盖只存内存
//（页面侧持有），首发落行时随 insertMessage 一并写入（与 promptId「随首发落行」同款）。
// 会话级覆盖结构（三列 '' = 未覆盖）
export interface ConversationOverride {
  modelProviderId: string;
  modelId: string;
  webSearchOverride: string;
}

// 查会话级覆盖（三态：null = 行不存在〔无行会话〕→ 调用方用内存覆盖；行在 = 按列值，
// '' = 未覆盖）
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

// 写会话级模型覆盖（providerId/modelId 传 '' = 清覆盖回默认源）。无行会话命中 0 行
// **不抛错**（0 行 = 会话还没落行，属正常——与 updateAssistantTools 的 0 行抛错〔目标被删
// 属异常〕语义不同）；返回受影响行数供调用方记账
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
// 全部模型）。清列而非删行——会话与历史消息不陪葬，落回默认源。返回清掉的会话行数
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

// 单独选择某模型的会话数（删除前使用检测）：modelProviderId/modelId 两列双条件 COUNT——
// 严格对，与 clearConversationModelOverride 同判据；bindArgs 走 ? 占位防注入（modelId 是
// 用户可填文本）。空对回 0（未配置语义）
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

// ── 会话推荐问题列（DB v34）──
// 语义（ChatDbMigrate v34 注释）：追问推荐 JSON 数组串存会话行，'' = 无；会话级**末条覆盖
// 写**，发送即清空写 ''，回放显示不重新生成。解析/序列化单源 = common/SuggestGen.ets，
// 本层只存取原串；写值不动 updatedAt；消费方 = SuggestGen 写回/清空 + ChatPageLoad 回放
// 装配 + 生成链重复触发守卫

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

// ═══ 会话格式态路由（K1 唯一路由真源的读写单点）═══
// 读写两侧一律经本组口判定会话态，禁各处直查 migrateState 列（防判据漂移）。态词表 =
// MessageBranchDb.CONV_STATE_*（冻结两值 graph / legacy；**非 graph 即墓碑**——历史
// migrating 残值与脏值同判）。

// 会话格式态读口：行不存在回 legacy（无行会话 = 未出生语义，I3——首次发送才建事实）；
// 读失败不静默吞成 legacy 会掩盖真 graph 态 → 上抛由调用方按「库异常」处置（P0-1）
export async function queryConversationMigrateState(conversationId: string): Promise<string> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates, ['migrateState']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      return result.getString(result.getColumnIndex('migrateState'));
    }
    return 'legacy';
  } finally {
    result.close();
  }
}

// 当前分支读口（graph 会话路由读写的分支真源；非 graph/无行 = ''——调用方以 '' 判非图态）
export async function queryConversationActiveBranch(conversationId: string): Promise<string> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  const result: relationalStore.ResultSet = await requireStore().query(predicates,
    ['migrateState', 'activeBranchId']);
  try {
    if (result.rowCount > 0 && result.goToNextRow()) {
      if (result.getString(result.getColumnIndex('migrateState')) !== 'graph') {
        return '';
      }
      return result.getString(result.getColumnIndex('activeBranchId'));
    }
    return '';
  } finally {
    result.close();
  }
}

// 当前分支写口（重试建替代分支后切换、导入恢复 activeBranchId、出生发布等——调用方须
// 保证会话已处 graph 态；本口不校验态，保持单点写值语义。消费方 = 出生原语
// ChatContextSource.bornGraphConversation 与重试链两处）
export async function setConversationActiveBranch(conversationId: string,
  branchId: string): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'activeBranchId': branchId };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  await requireStore().update(bucket, predicates);
}

// 会话可写路由读口 = ChatContextSource.conversationWritableRoute（其需调
// writeGraphCapabilityLevel 与出生原语，落本件即造环——外移彼件，本件只留格式态读写口）；
// ensureConversation 转导出供彼件建行用（签名不变）

// 按消息集查附件行：句柄委托入口——加载链（ChatPageLoad）经本函数消费，不直接触达
// AttachmentDb（依赖方向红线：ChatDb → AttachmentDb 单向）。空集短路等在同名实现内；
// 查询失败上抛由调用方留痕
export async function queryAttachmentsForMessages(
  messageIds: string[]): Promise<MessageAttachmentRow[]> {
  return queryAttachmentRowsForMessages(requireStore(), messageIds);
}

// ── 附件管理列表面委托（页面侧一律经本组入口消费，依赖方向红线同上；分页/空集短路/
// 投影口径全在 AttachmentDb 同名实现内，本层只补句柄）──
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

// 按会话附件计数（统计面板「附件数」行——委托形态同上三口）
export async function queryAttachmentCount(conversationId: string): Promise<number> {
  return countAttachmentsByConversation(requireStore(), conversationId);
}

// ── 聊天附件按时间清理委托（存储管理页「清理聊天附件」面板经本组入口消费，不直接触达
// AttachmentDb；档位派生与确认文案单源在 StorageStats，cutoffMs 由页面快照传入——开面板
// 一次算定、确认与执行携带同一值，「显示数 = 实删数」精确成立）──
// 读数（cutoffMs = null 即全部档全表合计）
export async function readAttachmentCleanPreview(cutoffMs: number | null):
  Promise<AttachmentTotalRow> {
  return readAttachmentCleanPreviewRow(requireStore(), cutoffMs);
}

// 删除编排（入链分批短事务：refs 成对清 + commit 后删文件；返回实删行数）
export async function deleteAttachmentsByCutoff(cutoffMs: number | null): Promise<number> {
  return deleteAttachmentsByCutoffRow(requireStore(), cutoffMs);
}

// 按附件行 id 单件删（行 + 文件成对铁律）：两段式同 deleteConversations——先删行取回
// localPath 集，再删文件（best-effort，失败留启动收敛自愈）。附件管理页单件删走本入口，
// 页面侧不碰文件原语。★ 入参是附件行 id 不是 messageId：一条消息可挂多件附件，按
// messageId 删会误伤同消息其余件
export async function deleteAttachments(attachmentIds: string[]): Promise<void> {
  const attachPaths: string[] = await deleteAttachmentsByIds(requireStore(), attachmentIds);
  removeAttachmentFiles(attachPaths);
}

// ── 工作区委托（工具域与管理页一律经本组入口消费，不直接触达 WorkspaceDb——依赖方向
// 红线同附件委托；闸判定/写序/失败自清全在同名实现内，本层只补句柄）──
// 全量列表（行集读取上限由调用方传入——读取面一律 WORKSPACE_ROWS_READ_MAX；ORDER BY
// updatedAt DESC）
export async function queryWorkspaceFiles(limit: number): Promise<WorkspaceFileRow[]> {
  return queryWorkspaceFileRows(requireStore(), limit);
}

// 合计（count + bytes，三闸判定与管理页统计共用）
export async function queryWorkspaceTotal(): Promise<WorkspaceTotalRow> {
  return queryWorkspaceTotalRowOf(requireStore());
}

// 按 (dir, name) 精确匹配（read 定位与 write 覆盖判定；显示名目录内唯一、跨目录可同名
//——定位恒二元组，dir '' = 根）
export async function queryWorkspaceFilesByName(dir: string,
  name: string): Promise<WorkspaceFileRow[]> {
  return queryWorkspaceFileRowsByName(requireStore(), dir, name);
}

// 保存文本文件（write 工具唯一写口：dir/名称闸 → 三闸 → 写文件 → 写行〔失败自清〕全编排；
// dir 缺省 '' = 根，目录不存在隐式创建）
export function saveWorkspaceText(name: string, content: string, source: string,
  conversationId: string, ownerAssistantId: string,
  dir: string = ''): Promise<WorkspaceSaveOutcome> {
  return saveWorkspaceTextFile(requireStore(), name, content, source, conversationId,
    ownerAssistantId, dir);
}

// 保存 xlsx 文件（workspace_write_xlsx 工具唯一落库口；编排 = WorkspaceDbXlsx 拆分件
//〔依赖方向 ChatDb → WorkspaceDbXlsx → WorkspaceDb 单向〕，本层只补句柄——tempPath =
// 产出核临时件且已过执行器反读自检）
export function saveWorkspaceXlsx(name: string, tempPath: string, source: string,
  conversationId: string, ownerAssistantId: string,
  dir: string = ''): Promise<WorkspaceSaveOutcome> {
  return saveWorkspaceXlsxFile(requireStore(), name, tempPath, source, conversationId,
    ownerAssistantId, dir);
}

// 编辑文本文件（workspace_edit 工具唯一落库口；编排 = WorkspaceDbEdit 拆分件——链内现读
//→ 三级级联匹配 → 闸 → 写回 → 行更新只动 size/updatedAt；链外先读后编硬门在执行器侧，
// 本层只补句柄）
export function editWorkspaceText(dir: string, name: string, oldText: string, newText: string,
  replaceAll: boolean, conversationId: string): Promise<WorkspaceEditOutcome> {
  return editWorkspaceTextFile(requireStore(), dir, name, oldText, newText, replaceAll,
    conversationId);
}

// ── 目录四操作委托（mkdir/rename/move/delete 工具动作壳）──
// 建文件夹（铸目录行有 DB 写入写链；逐段冲突检查 + 已存在幂等仍补铸缺失段行；source——
// 模型建 = 'assistant'、ui 用户建 = 'user'，追溯随调用方）
export function createWorkspaceDirOp(dir: string, source: string, conversationId: string,
  assistantId: string): Promise<WorkspaceEntryOpOutcome> {
  return createWorkspaceDir(requireStore(), dir, source, conversationId, assistantId);
}

// 目录行铸造（write·import 隐式建目录的入账面——HttpBinary 导入壳无 db 句柄经本口消费；
// 须在写链内调用）
export function ensureWorkspaceDirRowsOp(dir: string, source: string,
  conversationId: string, ownerAssistantId: string): Promise<void> {
  return ensureWorkspaceDirRows(requireStore(), dir, source, conversationId, ownerAssistantId);
}

// 重命名文件或文件夹（改名不覆盖；ext 相同零物理动作）
export function renameWorkspaceEntryOp(dir: string, name: string,
  newName: string): Promise<WorkspaceEntryOpOutcome> {
  return renameWorkspaceEntry(requireStore(), dir, name, newName);
}

// 移动文件或文件夹（toDir 必须已存在；文件夹环检查拒）
export function moveWorkspaceEntryOp(dir: string, name: string,
  toDir: string): Promise<WorkspaceEntryOpOutcome> {
  return moveWorkspaceEntry(requireStore(), dir, name, toDir);
}

// 删除文件或整个文件夹（先物理后行 + 对账自愈；删前统计随结果返回）
export function deleteWorkspaceEntryOp(dir: string,
  name: string): Promise<WorkspaceEntryOpOutcome> {
  return deleteWorkspaceEntry(requireStore(), dir, name);
}

// 按 id 单件删（行 + 文件成对铁律，管理页消费；先删行收集路径 → 删文件 best-effort；
// 入参 = workspace_files 行 id）。入链编排 = 拆分件 WorkspaceDbManage——原散写不入全局
// 写链，与在飞写事务并发触发官方 14800024（本层只补句柄）
export function deleteWorkspaceFiles(ids: string[]): Promise<void> {
  return deleteWorkspaceFilesQueued(requireStore(), ids);
}

// 清空工作区（全表删行 + 清空整个目录内容——孤儿残留一并覆盖；入链编排 =
// WorkspaceDbManage.clearWorkspaceAllQueued）
export function clearWorkspaceAll(): Promise<void> {
  return clearWorkspaceAllQueued(requireStore());
}

// 上传链直插（picker 拷入落文件后入行；source='user'，追溯两列恒空串；入链同三口口径）
export function insertWorkspaceFile(row: WorkspaceFileRow): Promise<void> {
  return insertWorkspaceFileQueued(requireStore(), row);
}

// 行 upsert（2026-10-01 笔 7：下载落盘与导入覆盖路——按 id REPLACE，覆盖与新建统一）
export function upsertWorkspaceFile(row: WorkspaceFileRow): Promise<void> {
  return upsertWorkspaceRow(requireStore(), row);
}

// 按 id 删行并取回相对路径集（2026-10-31 ZIP 三件笔：zip_extract 吸入中途失败的回滚删行
// 口——非入链裸委托〔供已在 runWriteQueued 写串行链内的工具编排链内直调，嵌套入链会挂死
// 全局写链〕；行删后文件删除由调用方按返回路径自理）
export function deleteWorkspaceRowsByIdsOp(ids: string[]): Promise<string[]> {
  return deleteWorkspaceRowsByIds(requireStore(), ids);
}

// 持久化某层目录自定义序（管理页文件夹段拖拽落定的唯一落库口；ids = 该层目录行全量 id
// 按新序排列，实现与入链/事务全在 WorkspaceDbDirOrder）
export function saveWorkspaceDirOrder(ids: string[]): Promise<void> {
  return saveWorkspaceDirOrderOf(requireStore(), ids);
}

// ── 识别文字委托（工具域与管理页/识别文字页一律经本组入口消费，不直接触达
// WorkspaceDbOcr——依赖方向红线同工作区委托；六列读写与纯函数全在彼件，本层只补句柄）──
// 单行六列读（行不存在 = null）
export function queryWorkspaceOcr(id: string): Promise<WorkspaceOcrRecord | null> {
  return queryWorkspaceOcrOf(requireStore(), id);
}

// 单行全列读（识别文字页重识别的行载荷读口；行不存在 = null）
export function queryWorkspaceRowById(id: string): Promise<WorkspaceFileRow | null> {
  return queryWorkspaceFileRowByIdOf(requireStore(), id);
}

// 有识别文本的行 id 集（管理页菜单两态标签轻量位；全文不进投影）
export function queryWorkspaceOcrHasText(ids: string[]): Promise<string[]> {
  return queryWorkspaceOcrHasTextOf(requireStore(), ids);
}

// 识别结果落库（识别链唯一写口；入写链；返回 false = 行已删幽灵写，调用方静默）
export function saveWorkspaceOcr(id: string, text: string, engine: string,
  fileMtimeMs: number, fileSize: number): Promise<boolean> {
  return saveWorkspaceOcrQueuedOf(requireStore(), id, text, engine, fileMtimeMs, fileSize);
}

// 校对保存（识别文字页返回链唯一写口；只写文本与校对时刻，不动指纹列）
export function saveWorkspaceOcrEdit(id: string, text: string): Promise<boolean> {
  return saveWorkspaceOcrEditQueuedOf(requireStore(), id, text);
}

// ── 临时产物区委托（页面与工具域一律经本组入口消费，不直接触达 WorkspaceDbTmp——依赖
// 方向红线同工作区委托；扫描/计数/删除为纯 fs 无句柄、转存传句柄，实现与三不红线全在彼件）──
export function listWorkspaceTmpFiles(conversationId: string): WorkspaceTmpScan {
  return listWorkspaceTmpFilesOf(conversationId);
}

export function listWorkspaceTmpGroups(): WorkspaceTmpGroupBrief[] {
  return listWorkspaceTmpGroupsOf();
}

export function countWorkspaceTmpFiles(conversationId: string): number {
  return countWorkspaceTmpFilesOf(conversationId);
}

export function workspaceTmpTotalBytes(): number {
  return workspaceTmpTotalBytesOf();
}

// 临时区数据总览（管理页「数据总览」面板临时侧载荷；一次扫全，分类与聚合在
// WorkspaceStatsUtil 纯函数）
export function scanWorkspaceTmpOverview(): WorkspaceDataStats {
  return scanWorkspaceTmpOverviewOf();
}

export function deleteWorkspaceTmpConversationOp(conversationId: string): void {
  deleteWorkspaceTmpConversationOf(conversationId);
}

export function deleteWorkspaceTmpFileOp(conversationId: string, fileName: string): void {
  deleteWorkspaceTmpFileOf(conversationId, fileName);
}

export function clearWorkspaceTmpAllOp(): void {
  clearWorkspaceTmpAllOf();
}

// 转存（临时件 → 正式工作区；编排全在 WorkspaceDbTmp.promoteWorkspaceTmpFile——入写链、
// 三闸、同名追加序号、行写失败自清）
export function promoteWorkspaceTmpFileOp(conversationId: string,
  fileName: string): Promise<PromoteOutcome> {
  return promoteWorkspaceTmpFileOf(requireStore(), conversationId, fileName);
}

// ── 文件夹挂载委托（管理页与工具执行器族一律经本组入口消费，不直接触达 MountDb——依赖
// 方向红线同工作区委托）。★ 系统侧授权动作（persist/revoke/check/activate）不在本组——
// 那是页面与工具编排层的 fileShare 调用，本组只管 folder_mounts 表行（两套真相的边界）──
// 全量清单（列表次序稳定 = createdAt ASC；件数上限闸在增行口内）
export async function queryFolderMounts(): Promise<FolderMountRow[]> {
  return queryFolderMountRows(requireStore());
}

// 增行（系统侧 persist 成功后调用；上限与同 dirUri 查重同链内置，命中抛中文错）
export function addFolderMount(name: string, dirUri: string, mode: number): Promise<void> {
  return insertFolderMountRow(requireStore(), name, dirUri, mode);
}

// 改名（纯标签写）
export function renameFolderMount(id: number, name: string): Promise<void> {
  return updateFolderMountName(requireStore(), id, name);
}

// 授权态回写（进页校验/切换模式/重新授权三处写点共用单口；dirUri 一并写回——重新授权
// 遇目录改名换址时随新选择更新）
export function updateFolderMountGrant(id: number, mode: number, dirUri: string,
  lastCheckAt: number, lastError: string): Promise<void> {
  return updateFolderMountGrantRow(requireStore(), id, mode, dirUri, lastCheckAt, lastError);
}

// 删行（移除流程的行侧半段；系统侧 revoke 由页面 best-effort 先行）
export function removeFolderMount(id: number): Promise<void> {
  return deleteFolderMountRow(requireStore(), id);
}

// 挂载文件拷入工作区（mount_copy_out 工具唯一落库口；编排 = WorkspaceDb.mountCopyIntoWorkspace
//——闸链与行 upsert 全在彼件，本层只补句柄。末参 source 缺省 = 工具面 'assistant'，用户面
// 浏览页「复制到工作区」传 'user'）
export function mountCopyToWorkspace(srcAbsPath: string, rawName: string, sizeBytes: number,
  conversationId: string, ownerAssistantId: string,
  dir: string = '', source: string = WORKSPACE_SOURCE_ASSISTANT): Promise<WorkspaceSaveOutcome> {
  return mountCopyIntoWorkspace(requireStore(), srcAbsPath, rawName, sizeBytes,
    conversationId, ownerAssistantId, dir, source);
}

// ── MCP 服务器委托（管理页、编辑页与 B6 工具域一律经本组入口消费，不直接触达 McpDb——
// 依赖方向红线同挂载委托）。★ Asset 编排收口在本层单点——「先 Asset 后 DB 行」写序
//（ProviderKeyDb.insertProviderKey 先例；DB 写失败时 Asset 组或留多余值，下次保存整组重写
// 自愈——低危已知边界）与删除级联的组清理都不散落调用方 ──
// 全量清单（次序稳定 = createdAt ASC, id ASC；件数上限闸在增行口内）
export async function queryMcpServers(): Promise<McpServerRow[]> {
  return queryMcpServerRows(requireStore());
}

// 新增服务器（编辑页保存链）：铸 id → **先 Asset 头值组整组重写** → 后 DB 行（Asset 先行
// 的失败形态优于反向：DB 行成功而 Asset 失败 = 行在值缺可提示重填；Asset 成功而 DB 失败 =
// 无主明文，下次保存整组重写自愈）。DB 侧上限/查重/校验三闸在 McpDb 增行口内单点把守
//（闸拒时 Asset 已写一组 = 上述低危边界）。headersJson = 元数据串
//（serializeMcpHeaderMeta 产物），headerValues = 与元数据等长的值数组（'' = 该行无值）；
// authKind / protocolVersion = v60 两列（认证方式意图与广告协议版本，取值域单源 =
// McpText / McpRpc）——原样透传，委托层不做二次判定
export async function addMcpServer(name: string, url: string, headersJson: string,
  headerValues: string[], authKind: string, protocolVersion: string): Promise<void> {
  const id: string = util.generateRandomUUID(true);
  await saveMcpHeaderValues(id, headerValues);
  await insertMcpServer(requireStore(), id, name, url, headersJson, authKind, protocolVersion);
}

// 编辑服务器（元数据整组替换）：写序同 add——先 Asset 组整组重写（留空保持原值的行由
// 调用方在 headerValues 里回填旧值）后 DB 行；查重排除自身与名称校验在 McpDb 改行口内；
// v60 两列同 add 原样透传
export async function editMcpServer(id: string, name: string, url: string,
  headersJson: string, headerValues: string[], authKind: string,
  protocolVersion: string): Promise<void> {
  await saveMcpHeaderValues(id, headerValues);
  await updateMcpServerRow(requireStore(), id, name, url, headersJson, authKind, protocolVersion);
}

// 读头值明文组（密钥读封口——B6 执行器拼请求头现取现用；行不存在回空数组）
export async function loadMcpServerHeaderValues(id: string): Promise<string[]> {
  const rows: McpServerRow[] = await queryMcpServerRows(requireStore());
  for (const row of rows) {
    if (row.id === id) {
      return loadMcpHeaderValues(id, parseMcpHeaderMeta(row.headersJson).length);
    }
  }
  return [];
}

// 启停开关（编辑页表单首行开关即时落库；0 = 注销注册表条目 + 不注入任何对话）
export function setMcpServerEnabled(id: string, enabled: boolean): Promise<void> {
  return updateMcpServerEnabledRow(requireStore(), id, enabled);
}

// 工具缓存回写单口（tools/list 同步成功/失败两路共用——成功 = 新缓存 + lastSyncAt + 清
// lastError；失败 = 缓存不动只回写摘要）
export function setMcpServerTools(id: string, toolsJson: string, lastSyncAt: number,
  lastError: string): Promise<void> {
  return updateMcpServerToolsRow(requireStore(), id, toolsJson, lastSyncAt, lastError);
}

// 删除服务器（级联三步编排单点）：①清 Asset 头值组（删行前元数据还在——按实际行数清；
// 行不存在 = 幂等静默返回）→ ②剔全部 assistants.mcpServers 引用 + ③删行（后两步在
// McpDb.deleteMcpServerCascade 同事务内，任一失败 rollBack 不半删）
export async function removeMcpServer(id: string): Promise<void> {
  const rows: McpServerRow[] = await queryMcpServerRows(requireStore());
  for (const row of rows) {
    if (row.id === id) {
      await removeMcpHeaderValues(id, parseMcpHeaderMeta(row.headersJson).length);
      break;
    }
  }
  await deleteMcpServerCascade(requireStore(), id);
}

async function touchConversation(conversationId: string, at: number): Promise<void> {
  const bucket: relationalStore.ValuesBucket = { 'updatedAt': at };
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('conversations');
  predicates.equalTo('id', conversationId);
  await requireStore().update(bucket, predicates);
}

// 会话列表时间推进公共口（★ 2026-09-26 自检位B 修复 B10/D10）：私有 touchConversation 的
// 薄封装（方法体零改动）。legacy 两写口（insertMessage / advanceRetryTimestamps）已随
// 2026-09-26 legacy 退役笔3 线性写路径退役删除，本口消费方单点 = ChatGraphWriteCtrl
// .commitOutputNode「图写链提交即推进列表时间」契约
export async function touchConversationUpdatedAt(conversationId: string,
  at: number): Promise<void> {
  return touchConversation(conversationId, at);
}
