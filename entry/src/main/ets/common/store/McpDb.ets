// MCP 服务器存储域（照 MountDb.ets 全套范本立件）：
// mcp_servers 表（v59 建）行读写——清单读取 / 增行（含上限、查重与名称兜底三闸）/ 元数据
// 更新 / 工具缓存回写单口 / 启停 / 删行（含 assistants.mcpServers 联动剔引用）。表语义与
// 列义单源 = ChatDbSchema.SQL_CREATE_MCP_SERVERS 注释；纯函数在 common/McpText.ets。
// · 依赖方向红线（照 MountDb 同款）：①本文件不 import ChatDb——store 句柄由调用方传入
//   （ChatDb → McpDb 单向，防环）；②页面与工具域一律经 ChatDb 委托入口消费（本文件不导出
//   给 UI 直碰 store 私有）；③写事务全入写串行链（DbWriteQueue.runWriteQueued——全局写链
//   纪律；「查上限查重 → 写」整段排队，并发添加不穿窗）。
// · Asset 编排不在本件：请求头值明文的存取（KeyStore 第九形态）与「先 Asset 后 DB」写序
//   收口在 ChatDb 委托层单点（addMcpServer / editMcpServer / removeMcpServer）——本件只见
//   headersJson 元数据串，永不接触明文值（密钥红线）。
// · 进备份（EXPORT_TABLES 含 mcp_servers）：服务器配置是用户搭建资产；头值明文不随备份走
//   （Asset 分流，导入后编辑态提示值缺失——B5 承接）。
import { relationalStore } from '@kit.ArkData';
import { runWriteQueued } from './DbWriteQueue';
import { MCP_SERVERS_MAX, isValidMcpServerName, parseEnabledMcpServerIds,
  serializeEnabledMcpServerIds } from '../McpText';

// 服务器行（列义见 ChatDbSchema.SQL_CREATE_MCP_SERVERS 注释；headersJson/toolsJson 只存
// 元数据与缓存，明文头值恒不在场）
export interface McpServerRow {
  id: string;
  name: string;
  url: string;
  enabled: boolean;
  headersJson: string;
  toolsJson: string;
  lastSyncAt: number;
  lastError: string;
  createdAt: number;
  // v60：认证方式意图标记与广告协议版本（列义单源 =
  // ChatDbSchema.SQL_CREATE_MCP_SERVERS 注释；底层链路零分叉——认证仍落头组）
  authKind: string;
  protocolVersion: string;
}

const MCP_COLUMNS: string = 'id, name, url, enabled, headersJson, toolsJson, lastSyncAt, ' +
  'lastError, createdAt, authKind, protocolVersion';

// 行映射（ResultSet → McpServerRow；enabled 的 INTEGER → boolean 归一单源）
function mapMcpServerRow(result: relationalStore.ResultSet): McpServerRow {
  return {
    id: result.getString(result.getColumnIndex('id')),
    name: result.getString(result.getColumnIndex('name')),
    url: result.getString(result.getColumnIndex('url')),
    enabled: result.getLong(result.getColumnIndex('enabled')) === 1,
    headersJson: result.getString(result.getColumnIndex('headersJson')),
    toolsJson: result.getString(result.getColumnIndex('toolsJson')),
    lastSyncAt: result.getLong(result.getColumnIndex('lastSyncAt')),
    lastError: result.getString(result.getColumnIndex('lastError')),
    createdAt: result.getLong(result.getColumnIndex('createdAt')),
    authKind: result.getString(result.getColumnIndex('authKind')),
    protocolVersion: result.getString(result.getColumnIndex('protocolVersion'))
  };
}

// 全量清单（管理页列表、B6 启动注册面 syncMcpTools、绑定卡共用；次序 = createdAt ASC,
// id ASC 稳定序——同步时间戳回写不重排列表。件数上限 MCP_SERVERS_MAX 由增行闸把守，
// 全表扫即查，不设 LIMIT〔有上限闸兜的有界集〕）
export async function queryMcpServers(db: relationalStore.RdbStore):
  Promise<McpServerRow[]> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT ' + MCP_COLUMNS + ' FROM mcp_servers ORDER BY createdAt ASC, id ASC');
  const rows: McpServerRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push(mapMcpServerRow(result));
    }
  } finally {
    result.close();
  }
  return rows;
}

// 增行（编辑页保存链经 ChatDb.addMcpServer 委托调用——Asset 头值组已先行落位，id 由
// 委托层铸造传入〔util.generateRandomUUID(true)，WorkspaceDb 同先例——Asset 别名
// 'aic.mcp.<serverId>.<序号>' 先于 DB 行存在，「先 Asset 后 DB」写序要求 id 先铸〕）。
// **查上限 + 查重 + 名称兜底校验与写同段排队**（并发添加不穿窗，照 MountDb
// insertFolderMountRow 同链判据）：达 MCP_SERVERS_MAX 抛中文错；同 name 已存在抛中文错
//（名称是三段工具名前缀段，重名 = 工具名冲突）；名称过不了 ^[A-Za-z0-9]+$ 抛中文错
//（编辑页实时校验是第一道，本闸兜底——数据层最后一道防线 P0-1 不静默）。失败即抛，
// 页面 toast 后不落行
export function insertMcpServer(db: relationalStore.RdbStore, id: string, name: string,
  url: string, headersJson: string, authKind: string, protocolVersion: string): Promise<void> {
  return runWriteQueued('insertMcpServer', async (): Promise<void> => {
    const existing: McpServerRow[] = await queryMcpServers(db);
    if (existing.length >= MCP_SERVERS_MAX) {
      throw new Error('最多支持 ' + MCP_SERVERS_MAX + ' 台 MCP 服务器，先删除一台再添加');
    }
    if (!isValidMcpServerName(name)) {
      throw new Error('服务器名只能用字母和数字');
    }
    for (const row of existing) {
      if (row.name === name) {
        throw new Error('已有名为「' + name + '」的服务器，请换一个名称');
      }
    }
    const now: number = Date.now();
    await db.executeSql('INSERT INTO mcp_servers (id, name, url, enabled, headersJson, ' +
      'toolsJson, lastSyncAt, lastError, createdAt, authKind, protocolVersion) ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id, name, url, 1, headersJson, '[]', 0, '', now, authKind, protocolVersion]);
  });
}

// 元数据更新（编辑页保存链经 ChatDb.editMcpServer 委托调用——name/url/headersJson 三值
// 整组替换；enabled 不在此口——开关有独立单口）。查重**排除自身**（改名撞他行才拦）+
// 名称兜底校验同 insert 闸（「增改闸」完整语义）；0 行抛错（目标行已被删除时调用方
// toast「已保存」= 撒谎，updateAssistantName 同款 P0-1 假成功防御）
export function updateMcpServer(db: relationalStore.RdbStore, id: string, name: string,
  url: string, headersJson: string, authKind: string,
  protocolVersion: string): Promise<void> {
  return runWriteQueued('updateMcpServer', async (): Promise<void> => {
    if (!isValidMcpServerName(name)) {
      throw new Error('服务器名只能用字母和数字');
    }
    const existing: McpServerRow[] = await queryMcpServers(db);
    for (const row of existing) {
      if (row.name === name && row.id !== id) {
        throw new Error('已有名为「' + name + '」的服务器，请换一个名称');
      }
    }
    const bucket: relationalStore.ValuesBucket = { 'name': name, 'url': url,
      'headersJson': headersJson, 'authKind': authKind, 'protocolVersion': protocolVersion };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('mcp_servers');
    predicates.equalTo('id', id);
    const rows: number = await db.update(bucket, predicates);
    if (rows === 0) {
      throw new Error('目标服务器行不存在（已被删除），保存未生效');
    }
  });
}

// 工具缓存回写单口（tools/list 同步成功/失败两路共用：成功 = 新缓存 + lastSyncAt + 清
// lastError；失败 = 缓存不动只回写 lastError——传原 toolsJson 即可）。B4 刷新键与 B5
// 保存后自动同步经 ChatDb.setMcpServerTools 委托调用
export function updateMcpServerTools(db: relationalStore.RdbStore, id: string, toolsJson: string,
  lastSyncAt: number, lastError: string): Promise<void> {
  return runWriteQueued('updateMcpServerTools', async (): Promise<void> => {
    const bucket: relationalStore.ValuesBucket = { 'toolsJson': toolsJson,
      'lastSyncAt': lastSyncAt, 'lastError': lastError };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('mcp_servers');
    predicates.equalTo('id', id);
    await db.update(bucket, predicates);
  });
}

// 启停开关（编辑页表单首行开关即时落库；0 = 注销注册表条目 + 不注入任何对话——消费在
// B6 syncMcpTools）
export function updateMcpServerEnabled(db: relationalStore.RdbStore, id: string,
  enabled: boolean): Promise<void> {
  return runWriteQueued('updateMcpServerEnabled', async (): Promise<void> => {
    const bucket: relationalStore.ValuesBucket = { 'enabled': enabled ? 1 : 0 };
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('mcp_servers');
    predicates.equalTo('id', id);
    await db.update(bucket, predicates);
  });
}

// 联动剔引用（assistants.mcpServers 列清该 serverId——SkillDb.clearSkillRefInAssistants
// 同形制）：全表读 assistants 的 (id, mcpServers) → 逐行解析剔除目标 id → **仅命中行**
// 回写（未命中不写：删服务器不该动没绑定过它的助手行）。JSON 列无法用 SQL 谓词下推
// 「是否含该 id」，只能全表遍历——助手数是用户手建小数据集，代价可忽略。
// ★ 调用方须在事务内调（本函数不自开事务，便于与删行同一原子单位）
async function clearMcpServerRefInAssistants(db: relationalStore.RdbStore,
  serverId: string): Promise<void> {
  const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
  const result: relationalStore.ResultSet = await db.query(predicates, ['id', 'mcpServers']);
  const targetIds: string[] = [];
  const targetValues: string[] = [];
  try {
    while (result.goToNextRow()) {
      const raw: string = result.getString(result.getColumnIndex('mcpServers'));
      const ids: string[] = parseEnabledMcpServerIds(raw);
      if (!ids.includes(serverId)) {
        continue;
      }
      targetIds.push(result.getString(result.getColumnIndex('id')));
      targetValues.push(serializeEnabledMcpServerIds(ids.filter((item: string): boolean =>
        item !== serverId)));
    }
  } finally {
    result.close();
  }
  for (let i = 0; i < targetIds.length; i++) {
    const bucket: relationalStore.ValuesBucket = { 'mcpServers': targetValues[i] };
    const update: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('assistants');
    update.equalTo('id', targetIds[i]);
    await db.update(bucket, update);
  }
}

// 删行级联（删除链③：Asset 头值组清理已在 ChatDb.removeMcpServer 委托层先行完成——
// Asset 无事务性，先清后删行；本函数只管 DB 侧原子单位）：同事务内「剔全部
// assistants.mcpServers 引用 → 删 mcp_servers 行」，任一步失败 rollBack 不半删（P0-1，
// SkillDb.deleteSkill 同款姿势——悬空引用行比不删更坏：绑定卡会显示已删服务器的开关）
export function deleteMcpServerCascade(db: relationalStore.RdbStore,
  id: string): Promise<void> {
  return runWriteQueued('deleteMcpServerCascade', async (): Promise<void> => {
    db.beginTransaction();
    try {
      await clearMcpServerRefInAssistants(db, id);
      await db.executeSql('DELETE FROM mcp_servers WHERE id = ?', [id]);
      db.commit();
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}
