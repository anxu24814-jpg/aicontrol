// 工作区管理页三写口的入链编排（W3-4 拆出）：管理页单删
// （deleteWorkspaceFilesQueued）/ 清空（clearWorkspaceAllQueued）/ 上传插行
// （insertWorkspaceFileQueued）三口的 runWriteQueued 收链编排。
// · 背景（14800024 口径）：三口原经 ChatDb 委托层散写不入全局写链——链内显式写
//   事务（saveWorkspaceDirOrder 的 beginTransaction）在飞时并发触发官方 14800024 直接
//   报错；收链后与工具路八口（save/edit/xlsx/promote/目录四操作）同口径。形制照
//   deleteWorkspaceEntry：链节内行删/目录清/插行与文件删除一并完成。
// · 为何独立成件而非并入 WorkspaceDb（反碎片下限②申报）：①彼件已越宪法 1200 硬线
//   （变更记录一千三百三十二节在案登记——拆后 1223 剔头续期），「越硬线新域不并入」
//   先例由其头注释与 WorkspaceDbDirOrder 拆分件两处自立；②本域与排序域（DirOrder）/
//   编辑编排（Edit）/ 临时区（Tmp）/ xlsx（Xlsx）职责均不属，并入任何既有拆分件都是
//   「XX 的一部分」式错缝；③工作区 store 域拆分件已超 10（反碎片下限④），本拆的额外
//   理由 = 硬线条款强制（宪法红线优先于反碎片美学）。
// · 依赖方向（拆分件纪律，零环）：ChatDb → 本件 → WorkspaceDb 单向（复用其行删/目录清/
//   插行/文件删四原语——供链节直调的裸原语约定件，本链节内调用零嵌套）；本件不 import
//   ChatDb；页面侧不经本件——一律走 ChatDb 同名委托口（WorkspaceDb 不导出给 UI 的依赖
//   红线同款）。
import { relationalStore } from '@kit.ArkData';
import { WorkspaceFileRow } from '../WorkspaceUtil';
import { runWriteQueued } from './DbWriteQueue';
import { clearWorkspaceRows, clearWorkspaceDirContents, deleteWorkspaceRowsByIds,
  insertWorkspaceRow, removeWorkspaceFiles } from './WorkspaceDb';

// 按 id 单件删（行 + 文件成对铁律，管理页消费）：链节内先删行收集路径 → 删文件
// best-effort（文件不存在 = 目标状态）
export function deleteWorkspaceFilesQueued(db: relationalStore.RdbStore,
  ids: string[]): Promise<void> {
  return runWriteQueued('deleteWorkspaceFiles', async (): Promise<void> => {
    removeWorkspaceFiles(await deleteWorkspaceRowsByIds(db, ids));
  });
}

// 清空工作区（全表删行 + 清空整个目录内容——不止删行内文件，孤儿残留一并覆盖，方案 §3.3
// 兜底口径）
export function clearWorkspaceAllQueued(db: relationalStore.RdbStore): Promise<void> {
  return runWriteQueued('clearWorkspaceAll', async (): Promise<void> => {
    await clearWorkspaceRows(db);
    clearWorkspaceDirContents();
  });
}

// 上传链直插（picker 拷入落文件后入行；source='user'，追溯两列恒空串）
export function insertWorkspaceFileQueued(db: relationalStore.RdbStore,
  row: WorkspaceFileRow): Promise<void> {
  return runWriteQueued('insertWorkspaceFile', (): Promise<void> => insertWorkspaceRow(db, row));
}
