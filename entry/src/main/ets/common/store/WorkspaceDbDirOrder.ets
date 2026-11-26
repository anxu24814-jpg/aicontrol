// 工作区目录排序域拆分件（v50；照 WorkspaceDbEdit /
// WorkspaceDbTmp 拆分先例——WorkspaceDb 已越 1200 硬线，新功能域不并入，独立成件）：
// workspace_files 目录行自定义序（sortOrder 列，v50）的两个存储原语——nextWorkspaceDirOrder
// （父层下一序，铸造与跨层移动的落底判据）与 saveWorkspaceDirOrder（管理页文件夹段长按
// 拖拽落定的整组回写口，ChatDb 同名委托透传）。
// · 排序键判据（坑69/70 生成域 vs 扫描域）：sortOrder **只目录行
//   消费**，生成域三写点 = ①本件 saveWorkspaceDirOrder 拖拽落定整组回写 0..n-1
//   ②目录行铸造两路（WorkspaceDb.ensureWorkspaceDirRows / reconcileWorkspace 对账登记）
//   取父层 max+1 落层底 ③move 跨层落目标层 max+1；文件行恒 0 不参与。查询扫描域 =
//   deriveWorkspaceDirListing（调用方一次查全的行集内存排序，排序键不构成任何 LIMIT
//   成员集判据）；queryWorkspaceFiles 的 ORDER BY updatedAt DESC + LIMIT **禁切**（成员集
//   判据，见该函数注释）。存量全 0 = 名称字典序兜底零漂移。禁切清单：①queryWorkspaceFiles
//   排序键 ②workspaceFilesInDir / deriveWorkspaceSessionGroups 等文件面排序 ③memories /
//   assistants / knowledge 各表 sortOrder 语义（各域独立）。
// · 依赖方向（拆分件纪律，零环）：本件只 import WorkspaceUtil 常量与 DbWriteQueue，
//   **不 import WorkspaceDb**（方向 = WorkspaceDb → 本件单向，句柄由调用方传入——
//   WorkspaceDbTmp 同款）；页面侧不经本件——一律走 ChatDb.saveWorkspaceDirOrder 委托口
//  （WorkspaceDb 不导出给 UI 的依赖红线同款）。
import { relationalStore } from '@kit.ArkData';
import { WORKSPACE_KIND_DIR } from '../WorkspaceUtil';
import { runWriteQueued } from './DbWriteQueue';

// 父层目录行下一序（铸造与跨层移动共用）：该父目录内目录行 max(sortOrder) + 1，空层 = 0
// ——新目录恒落层底（MemoryDb.insertMemory 落卡底同形制；COALESCE 显式兜底空层/空表，
// MAX 空组返回 NULL 不赌未文档化读取行为）。只在写链内调用（调用方均已入 runWriteQueued
// 或启动对账串行段）
export async function nextWorkspaceDirOrder(db: relationalStore.RdbStore,
  parentDir: string): Promise<number> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT COALESCE(MAX(sortOrder), 0) AS m FROM workspace_files WHERE kind = ? AND dir = ?',
    [WORKSPACE_KIND_DIR, parentDir]);
  try {
    if (result.goToNextRow()) {
      return result.getLong(result.getColumnIndex('m')) + 1;
    }
    return 0;
  } finally {
    result.close();
  }
}

// 持久化某层目录自定义序（管理页文件夹段拖拽落定后整组回写 sortOrder = 数组下标——
// saveMemoryOrder 同形制 + 事务加固：任一行失败 rollBack 整组零改动，不留半截序）。
// ids = 该层目录行全量 id（UI 侧按新序给出，ChatDb 委托口同名透传）。行缺失（拖拽期间
// 他端删除——写链内无并发，UI 行集陈旧窗口才可能）= UPDATE 零命中静默跳过，其余行序
// 仍一致落库，UI 下次 load 自然校准。入写链（写事务全入链纪律）。逐行 UPDATE 有界：
// 单层目录数 ≤ 目录行总量（件数硬闸 1000 的同族量级，页内单层通常个位数）
export function saveWorkspaceDirOrder(db: relationalStore.RdbStore, ids: string[]): Promise<void> {
  return runWriteQueued('saveWorkspaceDirOrder', async (): Promise<void> => {
    if (ids.length === 0) {
      return;
    }
    db.beginTransaction();
    try {
      for (let i = 0; i < ids.length; i++) {
        const bucket: relationalStore.ValuesBucket = { 'sortOrder': i };
        const predicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('workspace_files');
        predicates.equalTo('id', ids[i]);
        await db.update(bucket, predicates);
      }
      db.commit();
    } catch (e) {
      db.rollBack();
      throw e as Error;
    }
  });
}
