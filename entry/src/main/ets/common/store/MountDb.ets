// 文件夹挂载存储域（方案-文件夹挂载-20261008「地基 + 管理面」）：
// folder_mounts 表（v55 建 / v56 拆 aiAccess 列）行读写——清单读取 / 增行（含上限与查重闸）/
// 改名 / 授权态回写 / 删行。表语义与列义单源 = ChatDbSchema.SQL_CREATE_FOLDER_MOUNTS 注释。
// · 依赖方向红线（照 WorkspaceDb 同款）：①本文件不 import ChatDb——store 句柄由调用方
//   传入（ChatDb → MountDb 单向，防环）；②页面与工具域一律经 ChatDb 委托入口消费（本文件
//   不导出给 UI 直碰 store 私有）；③写事务全入写串行链（DbWriteQueue.runWriteQueued——全局
//   写链纪律；「查上限查重 → 写」整段排队，并发添加不穿窗）。
// · 不进备份（EXPORT_TABLES 零改动）：授权记录存系统侧、按设备隔离，带过去只有死行
// （方案 §3.6「备份排除」，对齐 Cube「不随备份和传送包迁移」）。
// · 系统侧授权动作（persistPermission / revokePermission / checkPersistentPermission 与
//   activate）**全在页面编排层**（MountManagePage）与工具域（ToolMount），本件只管本表行
//   ——系统授权与本地行是两套真相，本件的写只承载镜像与校验时间戳（方案 §3.4）。
// · ★ aiAccess 列 v56 整面拆除（决明拍板「允许 AI 使用」开关退役
//   ——想断访问直接移除挂载；访问门收敛为助手工具页组卡开关单层）。
import { relationalStore } from '@kit.ArkData';
import { runWriteQueued } from './DbWriteQueue';
import { MOUNT_MAX_COUNT, MOUNT_ROWS_READ_MAX } from '../MountUtil';

// 挂载行（列义见 ChatDbSchema.SQL_CREATE_FOLDER_MOUNTS 注释）
export interface FolderMountRow {
  id: number;
  name: string;
  dirUri: string;
  mode: number;
  createdAt: number;
  lastCheckAt: number;
  lastError: string;
}

const MOUNT_COLUMNS: string = 'id, name, dirUri, mode, createdAt, lastCheckAt, lastError';

// 全量清单（挂载件数上限 MOUNT_MAX_COUNT 由应用层把守——添加闸在 insertFolderMountRow
// 内，本读取给管理页与工具面共用；次序 = createdAt ASC, id ASC——列表稳定不
// 随校验时间戳回写重排）
export async function queryFolderMountRows(db: relationalStore.RdbStore):
  Promise<FolderMountRow[]> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT ' + MOUNT_COLUMNS + ' FROM folder_mounts ORDER BY createdAt ASC, id ASC LIMIT ?',
    [MOUNT_ROWS_READ_MAX]);
  const rows: FolderMountRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getLong(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        dirUri: result.getString(result.getColumnIndex('dirUri')),
        mode: result.getLong(result.getColumnIndex('mode')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        lastCheckAt: result.getLong(result.getColumnIndex('lastCheckAt')),
        lastError: result.getString(result.getColumnIndex('lastError'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 增行（管理页添加流程的落库口；系统侧 persist 成功后才可调用）。**查上限 + 查重与写
// 同段排队**（并发添加不穿窗——照工作区「查配额 → 写」同链判据）：达 MOUNT_MAX_COUNT 抛
// 中文错；同 dirUri 已存在抛中文错（方案 §3.4「同目录重复挂载：应用层按 dirUri 查重——
// 系统层重复 persist 行为未文档化，不赌」）。失败即抛，页面 toast 后不落行（P0-1 禁静默）
export function insertFolderMountRow(db: relationalStore.RdbStore, name: string, dirUri: string,
  mode: number): Promise<void> {
  return runWriteQueued('insertFolderMount', async (): Promise<void> => {
    const existing: FolderMountRow[] = await queryFolderMountRows(db);
    if (existing.length >= MOUNT_MAX_COUNT) {
      throw new Error('最多支持 ' + MOUNT_MAX_COUNT + ' 个挂载，先移除一个再添加');
    }
    for (const row of existing) {
      if (row.dirUri === dirUri) {
        throw new Error('这个文件夹已经挂载过了');
      }
    }
    const now: number = Date.now();
    await db.executeSql('INSERT INTO folder_mounts (name, dirUri, mode, createdAt, ' +
      'lastCheckAt, lastError) VALUES (?, ?, ?, ?, ?, ?)',
      [name, dirUri, mode, now, now, '']);
  });
}

// 改名（管理页卡头编辑键；纯标签写）
export function updateFolderMountName(db: relationalStore.RdbStore, id: number,
  name: string): Promise<void> {
  return runWriteQueued('renameFolderMount', async (): Promise<void> => {
    await db.executeSql('UPDATE folder_mounts SET name = ? WHERE id = ?', [name, id]);
  });
}

// 授权态回写（三处写点共用单口——进页校验 / 切换模式 / 重新授权）：mode 与 dirUri 一并
// 写回（切换模式 = 新模式位；重新授权 = 目录改名换址时 dirUri 随新选择更新），
// lastCheckAt = 本次校验时刻，lastError = 失败原因（'' = 正常）
export function updateFolderMountGrant(db: relationalStore.RdbStore, id: number, mode: number,
  dirUri: string, lastCheckAt: number, lastError: string): Promise<void> {
  return runWriteQueued('updateFolderMountGrant', async (): Promise<void> => {
    await db.executeSql('UPDATE folder_mounts SET mode = ?, dirUri = ?, lastCheckAt = ?, ' +
      'lastError = ? WHERE id = ?', [mode, dirUri, lastCheckAt, lastError, id]);
  });
}

// 删行（管理页移除流程的落库口；系统侧 revoke 是 best-effort——本件的删不依赖系统调用
// 成败，方案 §3.4「移除 = revoke + 删本地行」的行侧半段）
export function deleteFolderMountRow(db: relationalStore.RdbStore, id: number): Promise<void> {
  return runWriteQueued('deleteFolderMount', async (): Promise<void> => {
    await db.executeSql('DELETE FROM folder_mounts WHERE id = ?', [id]);
  });
}
