// 跨会话读/检索域拆分件（域级最小拆分）：只读查询单域——跨会话消息检索预筛
//（searchMessagesAcross，search_chats 工具候选面）+ get_chats 读取域四查询（最近会话
// 清单 / 标题精确定位 / 会话行 id 精读 / 图侧全量行）+ 会话消息统计（conversationMsgStats）
// + 标题与助手名反查（queryConversationTitles / queryConversationTitlesByIds /
// queryAssistantNameByIds / queryAssistantNameById）；行类型四件（ChatMessageHitRow /
// ChatReadConvRow / ChatReadWindowRow / ConversationMsgStats）随迁；写入面、单会话读写、
// 生命周期与全部委托族留在主件 ChatDb.ets。
// 为何不能并入：拆分前 ChatDb.ets 越 1200 硬线（宪法「单文件规模上限」）；本域职责缝一句
// 话说清（只读查询面，零写路径、零事务、零启动维护），照 WorkspaceDbManage / WorkspaceDbOcr
//「越硬线新域不并入」先例独立成件。
// ★ 2026-11-17 整体退役加密会话笔：本域原「locked = 0 硬排除」判据整族随功能退役（加密会话
// 与普通会话自此同权，检索/通读/清单三面归一）；v66 迁移已把存量 locked 清零，墓碑列零读写。
// 依赖方向（零环红线，坑50）：本件 → ChatDb 单向——句柄一律经 sharedRdbStore() 取用
//（store / initPromise 单例只允许主件一份，本件禁复制第二份）；ChatDb **禁 import 本件**
//（回引即环）。原四段自 ChatDb.ets 原样搬迁（方法体逐字，仅句柄取用点替换；判据注释随
// 代码同迁——含 searchMessagesAcross 的「本窗禁切 seq」候选集成员判据与「检索面恒定 =
// m.content 一列」成文判据）。
import { relationalStore } from '@kit.ArkData';
import { sharedRdbStore } from './ChatDb';

// 跨会话消息检索候选行（search_chats 工具预筛面——四字段轻行，reasoning/status 不取）：
// conversationId 供标题反查与「来自几个会话」统计，role 供结果行角色标注；打分/排序/片段
// 纯函数在 providers/ToolChatSearch（本接口是其入参类型）。★ id 列 = 图会话候选按可达
// 节点集过滤的唯一过滤键（无它则废弃分支节点的命中会被当成当前路径内容回给模型）
export interface ChatMessageHitRow {
  id: string;
  conversationId: string;
  role: string;
  content: string;
  createdAt: number;
}

// 跨会话消息检索（消费方 = ToolChatSearch SearchChatsExecutor）：LIKE 每词一式 OR 预筛
//（patterns 由调用侧纯函数产——已含 % 包裹与通配符转义，ESCAPE '\' 配对）→ 当前会话排除
//（'' = 无排除；「其他会话」语义）→ user/assistant 行（tool/notice 行不入检索面）→ 最近
// limit 条命中（createdAt DESC 保最近命中，相关度重排在调用侧端内做）。JOIN conversations
// 只服务可选助手范围条件（c.assistantId），无该条件时不过滤任何行。RdbPredicates 无 JOIN 与
// OR 组合能力，querySql 直写；本地 RDB 千行级 LIKE 全扫毫秒级，FTS 留二期。
// ★ 本窗口**禁切 seq**——判据 = 排序键的作用域必须覆盖扫描域：seq 是会话内 0 基序号
//（每个会话各自从 0 起铸、换会话即重置），本查询是 JOIN 全库混排 + LIMIT 截断 ⇒ 排序键
// 即**候选集成员判据**，切成 m.seq DESC 后「全库最近 N 条命中」退化成「各会话内序号最大
// 的那批」：短会话（新建/聊得少的）命中被系统性挤出候选集，用户刚在新会话聊过的内容搜
// 不到且零报错（执行级实证：405 命中 / LIMIT 300 ⇒ 新会话命中 0 条）。其余三窗口皆为
// 单会话查询（扫描域 == 序号域）⇒ 切序真等价，分野正是本判据。排序权威 =
// `m.createdAt DESC, m.rowid DESC`（rowid 决胜 = 同毫秒并列的确定化）——该禁切判据适用
// 于本参数引入后的所有调用方。
// ★ 可选时间窗（fromMs/toMs，0 = 无该边界，调用侧归一产物）与可选助手范围（assistantIds，
// 空表 = 不限，与会话列表/标题搜索同一范围口径）：条件**在场才拼**，缺省路径 SQL 逐字节
// 不变；千行级全扫毫秒级，不为此加索引——性能不许愿。
// ★ 检索面恒定 = `m.content` 一列（reasoning 不取，成文判据）：五家参照实现（RikkaHub /
// kelivo / Kimi Code / ZCode 等）一致不含思考段，且思考文本量大、推演性内容多，纳入只增
// 噪声；要动须先拍板并同步工具面口径与 UI 命中标记，禁单方面加列
export async function searchMessagesAcross(patterns: string[], excludeConversationId: string,
  limit: number, fromMs: number = 0, toMs: number = 0,
  assistantIds: string[] = []): Promise<ChatMessageHitRow[]> {
  if (patterns.length === 0) {
    return [];
  }
  const likeSql: string[] = patterns.map((_p: string): string => "m.content LIKE ? ESCAPE '\\'");
  const args: Array<string | number> = [excludeConversationId];
  for (const pattern of patterns) {
    args.push(pattern);
  }
  // 助手范围条件随占位符顺序追加（LIKE 段之后、时间窗段之前），limit 占位符恒居末
  let assistantSql: string = '';
  if (assistantIds.length > 0) {
    const marks: string[] = assistantIds.map((_id: string): string => '?');
    assistantSql = ' AND c.assistantId IN (' + marks.join(', ') + ')';
    for (const id of assistantIds) {
      args.push(id);
    }
  }
  // 时间窗条件随占位符顺序追加（LIKE 段之后、排序段之前），limit 占位符恒居末。
  // 判据 ≠0（非 >0）：0 = 未传哨兵，1970-01-01 及更早的合法边界毫秒可为 0/负值——
  // 按 >0 漏拼会让「to 在 1970 前」错误返回全量（应查空）
  let timeSql: string = '';
  if (fromMs !== 0) {
    timeSql += ' AND m.createdAt >= ?';
    args.push(fromMs);
  }
  if (toMs !== 0) {
    timeSql += ' AND m.createdAt <= ?';
    args.push(toMs);
  }
  args.push(limit);
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT m.id, m.conversationId, m.role, m.content, m.createdAt FROM messages m ' +
    'JOIN conversations c ON m.conversationId = c.id ' +
    'WHERE m.conversationId <> ? AND m.role IN (\'user\', \'assistant\') ' +
    'AND (' + likeSql.join(' OR ') + ')' + assistantSql + timeSql + ' ' +
    'ORDER BY m.createdAt DESC, m.rowid DESC LIMIT ?', args);
  const rows: ChatMessageHitRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
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

// ── 跨会话读取查询（get_chats 工具；消费方 = ToolChatSearch GetChatsExecutor）：三查询
// 均带当前会话排除（「其他会话」语义，searchMessagesAcross 同款）。行类型轻列（不取无关
// 列）；全部有界（LIMIT/COUNT 单查），禁逐行查（P1-2）。

// 会话轻行（list 清单与标题定位共用——三列恰为渲染所需）
export interface ChatReadConvRow {
  id: string;
  title: string;
  updatedAt: number;
}

// 消息窗行（read 通读——id/role/content/createdAt 四列恰为渲染与图路径过滤所需，reasoning/
// status 不取）。★ id 列 = 图会话窗口按可达节点集过滤并按链序重排的唯一过滤键（role/
// content 都非唯一）
export interface ChatReadWindowRow {
  id: string;
  role: string;
  content: string;
  createdAt: number;
}

// 最近会话清单（list 动作）：可选当前会话排除（excludeId '' = 无排除——执行器中转键空值
// 兜底，同 searchMessagesAcross），updatedAt DESC 限 limit
export async function queryRecentConversationsForRead(limit: number,
  excludeConversationId: string): Promise<ChatReadConvRow[]> {
  let sql: string = 'SELECT id, title, updatedAt FROM conversations';
  const args: Array<string | number> = [];
  if (excludeConversationId !== '') {
    sql += ' WHERE id <> ?';
    args.push(excludeConversationId);
  }
  sql += ' ORDER BY updatedAt DESC LIMIT ?';
  args.push(limit);
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(sql, args);
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

// 标题精确定位（read 动作）：title 精确等值（trim 在执行器侧做）；多行 = 同名歧义
//（执行器拒歧义），行空 = 0 命中（执行器回名单引导重试）
export async function queryConversationIdByTitle(title: string): Promise<ChatReadConvRow[]> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT id, title, updatedAt FROM conversations WHERE title = ?', [title]);
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

// 会话行按 id 精确读取（read 动作 id 路——消费方 ToolChatSearch GetChatsExecutor）：
// id 主键唯一，单行或 null，无多命中态
export async function queryConversationRowByIdForRead(conversationId: string):
  Promise<ChatReadConvRow | null> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT id, title, updatedAt FROM conversations WHERE id = ?',
    [conversationId]);
  let row: ChatReadConvRow | null = null;
  try {
    if (result.goToNextRow()) {
      row = {
        id: result.getString(result.getColumnIndex('id')),
        title: result.getString(result.getColumnIndex('title')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt'))
      };
    }
  } finally {
    result.close();
  }
  return row;
}

// 消息窗全量行（graph 会话读面专用）：一次取本会话全部 user/assistant 行，供调用侧按
// 可达节点集过滤 + 按链序重排后再切片——**排序键不外露**（SQL 序只作确定性基线，图会话
// 真序 = parent 链，见 ChatContextSource.readReachableNodeIds 头注释）。为什么整会话取回
// 而不分页：跨会话读取工具是低频人工动作（一次 read = 一次用户提问），会话行数量级百级、
// 轻列四列——性能不许愿红线：实测卡顿前不上分页
export async function queryConversationRowsForRead(
  conversationId: string): Promise<ChatReadWindowRow[]> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
    'SELECT m.id, m.role, m.content, m.createdAt FROM messages m ' +
    'WHERE m.conversationId = ? AND m.role IN (\'user\', \'assistant\') ' +
    'ORDER BY m.seq ASC',
    [conversationId]);
  const rows: ChatReadWindowRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
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

// 会话消息统计行：单行聚合——三角色计数 + 首末时间。口径：user/assistant 为「对话消息」
//（消息总数 = 两者和），tool 卡单列「工具调用」，notice 提示条不入统计；首末时间只取
// user/assistant 行（时间跨度与消息总数同基）。空会话各值为 0 = 真零（面板时间卡以
// firstAt 0 判「无行不显」）；查询异常由调用方降级（0 与未知区分同面板既有口径）
export interface ConversationMsgStats {
  userCount: number;
  assistantCount: number;
  toolCount: number;
  firstAt: number;
  lastAt: number;
}

export async function conversationMsgStats(conversationId: string): Promise<ConversationMsgStats> {
  const result: relationalStore.ResultSet = await sharedRdbStore().querySql(
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

// 按 id 集查标题的私有 helper（两反查口共用「IN 集一次查回填 Map」段；行缺失〔JOIN 已
// 保证理论不发生 / 会话已删真实会发生〕不进 Map，调用侧按语义兜底）
async function queryTitleMapByIds(ids: string[]): Promise<Map<string, string>> {
  const titles: Map<string, string> = new Map<string, string>();
  if (ids.length === 0) {
    return titles;
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('conversations');
  predicates.in('id', ids);
  const result: relationalStore.ResultSet = await sharedRdbStore().query(predicates, ['id', 'title']);
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

// 候选行会话标题批量反查（与检索同一消费方）：IN 集去重一次查回，禁逐行查（P1-2）；
// 行缺失（JOIN 已保证理论不发生）不进 Map，调用侧回「未命名会话」
export async function queryConversationTitles(rows: ChatMessageHitRow[]): Promise<Map<string, string>> {
  const ids: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const row of rows) {
    if (!seen.has(row.conversationId)) {
      seen.add(row.conversationId);
      ids.push(row.conversationId);
    }
  }
  return queryTitleMapByIds(ids);
}

// 按会话 id 集反查标题（工作区管理页会话聚合视图消费；输入形态 = id 数组〔UI 场景无命中
// 行载荷〕，与上行命中行数组口分工）：去重（'' 恒不入查——未关联组无会话可反查）→ 空集
// 短路 → IN 一次查回，禁逐行查（P1-2）；**返回 Map 供调用方立即消费**（异步装配时合并进
// 可观察数组），禁直接存进 @State——V1 对 Map 无可观察先例
export async function queryConversationTitlesByIds(ids: string[]): Promise<Map<string, string>> {
  const unique: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const id of ids) {
    if (id !== '' && !seen.has(id)) {
      seen.add(id);
      unique.push(id);
    }
  }
  return queryTitleMapByIds(unique);
}

// ── 助手名反查（工作区助手文件夹显示名单源反查；两消费点 = 管理页文件夹段目录行卡与
//    面包屑段名）。为何直查 assistants 表而不引 AssistantDb：本域拆出后引彼件虽已不成环，
//    沿留只读两列直查原形态不动（零改搬迁，禁顺手重构）；直查先例 = ChatDbMigrate（迁移
//    链）/ MemoryDb（助手库归属守卫）。行缺失不进 Map / 回 ''——调用方按「反查失败回退
//    原始目录名」消费，不谎报 ──
export async function queryAssistantNameByIds(ids: string[]): Promise<Map<string, string>> {
  const names: Map<string, string> = new Map<string, string>();
  const unique: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const id of ids) {
    if (id !== '' && !seen.has(id)) {
      seen.add(id);
      unique.push(id);
    }
  }
  if (unique.length === 0) {
    return names;
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('assistants');
  predicates.in('id', unique);
  const result: relationalStore.ResultSet =
    await sharedRdbStore().query(predicates, ['id', 'name']);
  try {
    while (result.goToNextRow()) {
      names.set(result.getString(result.getColumnIndex('id')),
        result.getString(result.getColumnIndex('name')));
    }
  } finally {
    result.close();
  }
  return names;
}

// 按单个助手 id 查名（'' = 查不到——面包屑单点消费的便捷口，批量口同源）
export async function queryAssistantNameById(id: string): Promise<string> {
  if (id === '') {
    return '';
  }
  const names: Map<string, string> = await queryAssistantNameByIds([id]);
  return names.get(id) ?? '';
}
