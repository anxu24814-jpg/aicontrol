// 工作区目录四操作域（自 WorkspaceDb.ets 外迁拆分，命名照 WorkspaceDbManage /
// WorkspaceDbEdit 先例）：mkdir / rename / move / delete 四工具动作壳（闸 → 定位 → 冲突
// 检查 → 先物理后行 + 失败回滚 + 启动对账自愈三重兜底）与 (dir, name) 定位面单源；
// WorkspaceEntryOpOutcome 结果形态 + EntryLocation 五载荷四态定位在此单源——消费方 =
// ChatDb 四委托口透传 + ToolWorkspace 四执行器（经委托）+ WorkspaceManagePage。
// 为何不能并入：主件 WorkspaceDb.ets 越行数硬线，四操作是独立功能域（动作壳编排 +
// 物理/行写序铁律），并入 Manage / Edit / DirOrder 任一拆分件均跨域。主件保留行/IO
// 原语与启动对账，本件单向 import 主件与 WorkspaceUtil（依赖方向 ChatDb →
// WorkspaceDb(族) → WorkspaceUtil 单向不变；本件禁引 ChatDb 防环）。ensureWorkspaceDir
// 与 dirChildSegments 留主件（Tool 域断言直读其 export 形态）。

import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkspaceFileRow, isWorkspaceDirRow, classifyWorkspaceName, extOfWorkspaceName,
  joinDirName, relativeWorkspacePath, workspaceDirChainReject, workspaceDirRejectReason,
  workspaceFileName, workspaceMimeOf, workspaceNameRejectReason,
  WORKSPACE_DIR_NAME, WORKSPACE_ROWS_READ_MAX } from '../WorkspaceUtil';
import { dirChildSegments, deleteWorkspaceRowsByIds, ensureWorkspaceDir,
  ensureWorkspaceDirRows, physicalWorkspaceDirExists, queryWorkspaceFiles,
  queryWorkspaceFilesByName, removeWorkspaceFiles, removeWorkspaceTree,
  workspaceFilesDir } from './WorkspaceDb';
import { runWriteQueued } from './DbWriteQueue';
import { nextWorkspaceDirOrder } from './WorkspaceDbDirOrder';

// ── 目录四操作（四动作全程入写链——链纪律口径 DbWriteQueue.ets:8-11）──
// 操作结果（四操作共用；失败态数值恒 0，执行器按 isDir / fileCount / totalBytes 组回执）
export interface WorkspaceEntryOpOutcome {
  ok: boolean;
  errorText: string;
  isDir: boolean; // 定位判定的对象形态（false = 文件 / true = 文件夹）
  alreadyExists: boolean; // mkdir 专用：目录已存在 = 幂等成功（回执注明）
  fileCount: number; // delete 文件夹：删前件数统计
  totalBytes: number; // delete 文件夹：删前合计统计
}

const entryOpFailed = (text: string): WorkspaceEntryOpOutcome => ({ ok: false,
  errorText: text, isDir: false, alreadyExists: false, fileCount: 0, totalBytes: 0 });

// 定位结果：file 命中 / 文件夹（目录行或物理探测）后代行集 / 二义 / 未命中 五载荷四态
interface EntryLocation {
  state: string; // 'file' | 'dir' | 'amb' | 'none'
  fileRow?: WorkspaceFileRow;
  dirRow?: WorkspaceFileRow; // 文件夹态自身的目录行；undefined = 无行空目录（物理探测态）
  descendants?: WorkspaceFileRow[];
}

// (dir, name) 定位（rename/move/delete 共用一套规则）：先查行——文件行命中 = 文件（同段名
// 又有文件夹前缀 = 二义拒，不猜）；**目录行命中 = 文件夹态**（空文件夹一等行直接定位——
// dirRow 在场，后代行集照常收集供删改移统计）；零命中查后代行集（dir 前缀 = dir/name 的
// 行）；**后代也零 = 物理探测兜底**（对账未完成窗口 / 无行历史态的空物理目录按零后代文件
// 夹定位，可删可改名可移动）。后代行收集一律内存过滤（startsWith 前缀比较——**禁 SQL
// LIKE**，dir 段合法含 % _ 通配注入面，后人勿「优化」回去）
async function locateWorkspaceEntry(db: relationalStore.RdbStore,
  dir: string, name: string): Promise<EntryLocation> {
  const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(db, dir, name);
  if (matches.length > 1) {
    return { state: 'amb' };
  }
  const childPath: string = joinDirName(dir, name);
  const descendants: WorkspaceFileRow[] = [];
  if (matches.length === 1) {
    const all: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    for (const row of all) {
      if (row.dir === childPath || row.dir.startsWith(childPath + '/')) {
        descendants.push(row);
      }
    }
    if (isWorkspaceDirRow(matches[0])) {
      return { state: 'dir', dirRow: matches[0], descendants: descendants };
    }
    return descendants.length > 0 ? { state: 'amb', descendants: descendants } :
      { state: 'file', fileRow: matches[0] };
  }
  const all: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
  for (const row of all) {
    if (row.dir === childPath || row.dir.startsWith(childPath + '/')) {
      descendants.push(row);
    }
  }
  if (descendants.length > 0) {
    return { state: 'dir', descendants: descendants };
  }
  // 物理探测兜底：无行空目录（filesDir 未就绪时跳过探测 = 维持 none 原语义）
  const filesDir: string = workspaceFilesDir();
  if (filesDir !== '' && physicalWorkspaceDirExists(filesDir + '/' +
    WORKSPACE_DIR_NAME + '/' + childPath)) {
    return { state: 'dir', descendants: [] };
  }
  return { state: 'none' };
}

// 建文件夹（mkdir 工具动作壳）：dir 闸 → 逐段冲突检查（dir 每个前缀段撞文件行即拒，含
// 末段）→ 已存在幂等（末段目录行或物理目录在场，仍**补铸缺失段行**——历史物理目录无行
// 时入账）→ 物理隐式创建全中间层 → **目录行铸造**。★ 铸造目录行 = 有 DB 写，**入写链**
//（原「纯 fs 不入链」口径废止）
export function createWorkspaceDir(db: relationalStore.RdbStore, dir: string,
  source: string, conversationId: string,
  ownerAssistantId: string): Promise<WorkspaceEntryOpOutcome> {
  return runWriteQueued('createWorkspaceDir', async (): Promise<WorkspaceEntryOpOutcome> => {
    const reject: string = workspaceDirRejectReason(dir);
    if (reject !== '') {
      return entryOpFailed(reject);
    }
    if (dir === '') {
      return entryOpFailed('目录路径不能为空');
    }
    const chainReject: string = workspaceDirChainReject(
      await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX), dir);
    if (chainReject !== '') {
      return entryOpFailed(chainReject);
    }
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return entryOpFailed('工作区目录未就绪，无法创建文件夹');
    }
    const absDir: string = filesDir + '/' + WORKSPACE_DIR_NAME + '/' + dir;
    const lastSeg: string = dir.substring(dir.lastIndexOf('/') + 1);
    const parentDir: string = dir.indexOf('/') < 0 ? '' :
      dir.substring(0, dir.lastIndexOf('/'));
    // 已存在判定：末段目录行在场 或 物理目录在场（文件行撞名已被逐段检查先拒）
    const lastHits: WorkspaceFileRow[] =
      await queryWorkspaceFilesByName(db, parentDir, lastSeg);
    let already = false;
    for (const row of lastHits) {
      if (isWorkspaceDirRow(row)) {
        already = true;
      }
    }
    already = already || physicalWorkspaceDirExists(absDir);
    try {
      ensureWorkspaceDir(dir);
      await ensureWorkspaceDirRows(db, dir, source, conversationId, ownerAssistantId);
    } catch (e) {
      return entryOpFailed('文件夹创建失败：' + (e as Error).message);
    }
    return { ok: true, errorText: '', isDir: true, alreadyExists: already, fileCount: 0,
      totalBytes: 0 };
  });
}

// 重命名文件或文件夹（rename 工具动作壳）：同目录内改名不换位置；改名不覆盖（目标同名
// = 拒，拍板——覆盖是 write 的显式语义，rename 静默覆盖易误删）；ext 相同零物理动作。
// 原子序 = 先物理后行 + 行失败回滚物理（尽力）+ 启动对账自愈三重兜底（非真事务）
export function renameWorkspaceEntry(db: relationalStore.RdbStore, dir: string, name: string,
  newName: string): Promise<WorkspaceEntryOpOutcome> {
  return runWriteQueued('renameWorkspaceEntry', async (): Promise<WorkspaceEntryOpOutcome> => {
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return entryOpFailed(dirReject);
    }
    const nameReject: string = workspaceNameRejectReason(newName);
    if (nameReject !== '') {
      return entryOpFailed(nameReject);
    }
    const loc: EntryLocation = await locateWorkspaceEntry(db, dir, name);
    if (loc.state === 'none') {
      return entryOpFailed('工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
        '没有名为「' + name + '」的文件或文件夹。请先用 workspace_list 查看该目录的内容。');
    }
    if (loc.state === 'amb') {
      return entryOpFailed('该位置存在同名的文件与文件夹，无法确定要改哪一个。请先在管理页处理或分开操作。');
    }
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return entryOpFailed('工作区目录未就绪，无法重命名');
    }
    const now: number = Date.now();
    // 自引用无操作（rename 同名 = 幂等成功）——文件路同名经下方冲突检查 selfId 排除本就
    // 放行（零物理动作仅行刷新），文件夹路会被 dirChildSegments（段名含自身）与物理探测
    //（命中自身）误拒且「会覆盖它」文案失实；两态统一在此短路，isDir 按定位形态给
    if (newName === name) {
      return { ok: true, errorText: '', isDir: loc.state === 'dir', alreadyExists: false,
        fileCount: 0, totalBytes: 0 };
    }
    // 目标名冲突检查（改名不覆盖）：同目录既有文件（排除自身，自身含文件行与目录行两态）/
    // 同段名子文件夹（含空目录段名）/ 目标位置已是物理目录（探测兜底——行未补窗口，
    // renameSync 对已存在目录目标的语义不赌）
    const targetClashes: WorkspaceFileRow[] =
      await queryWorkspaceFilesByName(db, dir, newName);
    const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    let selfId = '';
    if (loc.state === 'file' && loc.fileRow !== undefined) {
      selfId = loc.fileRow.id;
    } else if (loc.state === 'dir' && loc.dirRow !== undefined) {
      selfId = loc.dirRow.id;
    }
    const clashOther: boolean = targetClashes.some((row: WorkspaceFileRow): boolean =>
      row.id !== selfId);
    if (clashOther || dirChildSegments(allRows, dir).indexOf(newName) >= 0 ||
      physicalWorkspaceDirExists(filesDir + '/' + WORKSPACE_DIR_NAME +
        (dir === '' ? '' : '/' + dir) + '/' + newName)) {
      return entryOpFailed('该位置已有同名文件或文件夹，改名会覆盖它，已取消。请换一个名称。');
    }
    if (loc.state === 'file' && loc.fileRow !== undefined) {
      const row: WorkspaceFileRow = loc.fileRow;
      const oldExt: string = extOfWorkspaceName(row.name);
      const newExt: string = extOfWorkspaceName(newName);
      const sameExt: boolean = oldExt === newExt;
      const dirAbs: string = filesDir + '/' + WORKSPACE_DIR_NAME +
        (dir === '' ? '' : '/' + dir);
      if (!sameExt) {
        // 物理改名（扩展名变了 → 物理名随新 ext 重铸；renameSync 对文件原子）
        try {
          fs.renameSync(dirAbs + '/' + workspaceFileName(row.id, oldExt),
            dirAbs + '/' + workspaceFileName(row.id, newExt));
        } catch (e) {
          return entryOpFailed('文件重命名失败：' + (e as Error).message);
        }
      }
      // 行更新（ext 相同 = 零物理动作仅行；ext 不同 = kind/mime 从新名重派生，classify
      // 未命中保留原 kind——不凭改名制造 other）
      const newKindClassified: string = classifyWorkspaceName(newName);
      const bucket: relationalStore.ValuesBucket = sameExt ?
        { 'name': newName, 'updatedAt': now } :
        { 'name': newName, 'kind': newKindClassified === '' ? row.kind : newKindClassified,
          'mime': workspaceMimeOf(newName),
          'localPath': relativeWorkspacePath(dir, workspaceFileName(row.id, newExt)),
          'updatedAt': now };
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('workspace_files');
      predicates.equalTo('id', row.id);
      try {
        await db.update(bucket, predicates);
      } catch (e) {
        if (!sameExt) {
          try {
            fs.renameSync(dirAbs + '/' + workspaceFileName(row.id, newExt),
              dirAbs + '/' + workspaceFileName(row.id, oldExt));
          } catch {
            // 回滚也失败：物理已在新位、行指向旧名——下次启动对账自愈（行删 + 新位补录）
          }
        }
        return entryOpFailed('工作区记录更新失败：' + (e as Error).message);
      }
      return { ok: true, errorText: '', isDir: false, alreadyExists: false, fileCount: 0,
        totalBytes: 0 };
    }
    // 文件夹改名：物理整目录 renameSync + 目录行自身 name/localPath 更新 + 后代行 dir 前缀
    // 重写（后代含子目录行——localPath 重写分流：文件行 = 物理名尾段拼接，目录行 = 整串；
    // 无行空目录探测态 = dirRow 缺省，零行更新纯物理改）
    const descendants: WorkspaceFileRow[] = loc.descendants ?? [];
    const childPath: string = joinDirName(dir, name);
    const childNewPath: string = joinDirName(dir, newName);
    const parentAbs: string = filesDir + '/' + WORKSPACE_DIR_NAME +
      (dir === '' ? '' : '/' + dir);
    try {
      fs.renameSync(parentAbs + '/' + name, parentAbs + '/' + newName);
    } catch (e) {
      return entryOpFailed('文件夹重命名失败：' + (e as Error).message);
    }
    try {
      if (loc.dirRow !== undefined) {
        const bucketSelf: relationalStore.ValuesBucket = { 'name': newName,
          'localPath': relativeWorkspacePath(dir, newName), 'updatedAt': now };
        const predSelf: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('workspace_files');
        predSelf.equalTo('id', loc.dirRow.id);
        await db.update(bucketSelf, predSelf);
      }
      for (const row of descendants) {
        const newDir: string = row.dir === childPath ? childNewPath :
          childNewPath + row.dir.substring(childPath.length);
        const tail: string = row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
        const newLocalPath: string = isWorkspaceDirRow(row) ?
          WORKSPACE_DIR_NAME + '/' + newDir : relativeWorkspacePath(newDir, tail);
        const bucket: relationalStore.ValuesBucket = { 'dir': newDir,
          'localPath': newLocalPath, 'updatedAt': now };
        const predicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('workspace_files');
        predicates.equalTo('id', row.id);
        await db.update(bucket, predicates);
      }
    } catch (e) {
      try {
        fs.renameSync(parentAbs + '/' + newName, parentAbs + '/' + name);
      } catch {
        // 回滚也失败：物理在新位、行指旧位——下次启动对账自愈
      }
      return entryOpFailed('工作区记录更新失败：' + (e as Error).message);
    }
    return { ok: true, errorText: '', isDir: true, alreadyExists: false, fileCount: 0,
      totalBytes: 0 };
  });
}

// 移动文件或文件夹（move 工具动作壳）：toDir 必须已存在（防拼写静默建目录——移动是搬运
// 不是生产）；移动文件夹时环检查（toDir 位于自身之下 = 拒）；物理 renameSync 整树搬。
// 原子序同 rename：先物理后行 + 回滚 + 对账自愈
export function moveWorkspaceEntry(db: relationalStore.RdbStore, dir: string, name: string,
  toDir: string): Promise<WorkspaceEntryOpOutcome> {
  return runWriteQueued('moveWorkspaceEntry', async (): Promise<WorkspaceEntryOpOutcome> => {
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return entryOpFailed(dirReject);
    }
    const toDirReject: string = workspaceDirRejectReason(toDir);
    if (toDirReject !== '') {
      return entryOpFailed(toDirReject);
    }
    const filesDir: string = workspaceFilesDir();
    if (filesDir === '') {
      return entryOpFailed('工作区目录未就绪，无法移动');
    }
    // toDir 必须已存在且是目录（不用 ensureWorkspaceDir——那会隐式创建；判定用
    // physicalWorkspaceDirExists——目标是个文件时不赌 renameSync 语义）
    const toDirAbs: string = filesDir + '/' + WORKSPACE_DIR_NAME +
      (toDir === '' ? '' : '/' + toDir);
    if (!physicalWorkspaceDirExists(toDirAbs)) {
      return entryOpFailed('目标目录「' + toDir + '」不存在。请先用 workspace_mkdir 创建，或检查目录路径是否写错。');
    }
    const loc: EntryLocation = await locateWorkspaceEntry(db, dir, name);
    if (loc.state === 'none') {
      return entryOpFailed('工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
        '没有名为「' + name + '」的文件或文件夹。请先用 workspace_list 查看该目录的内容。');
    }
    if (loc.state === 'amb') {
      return entryOpFailed('该位置存在同名的文件与文件夹，无法确定要移动哪一个。请先在管理页处理或分开操作。');
    }
    // 环检查（文件夹）：toDir 等于或位于 dir/name 之下 = 拒
    const childPath: string = joinDirName(dir, name);
    if (loc.state === 'dir' &&
      (toDir === childPath || toDir.startsWith(childPath + '/'))) {
      return entryOpFailed('不能把文件夹移动到它自己的子文件夹里。请换一个目标目录。');
    }
    // 自引用无操作（move 到自身当前所在层 = 幂等成功）——理由同 rename 的同名短路（文件夹
    // 路会被段名/物理探测命中自身误拒），两态统一在此短路
    if (toDir === dir) {
      return { ok: true, errorText: '', isDir: loc.state === 'dir', alreadyExists: false,
        fileCount: 0, totalBytes: 0 };
    }
    const now: number = Date.now();
    let selfId = '';
    if (loc.state === 'file' && loc.fileRow !== undefined) {
      selfId = loc.fileRow.id;
    } else if (loc.state === 'dir' && loc.dirRow !== undefined) {
      selfId = loc.dirRow.id;
    }
    // 冲突检查：目标目录内同显示名文件（排除自身，自身含文件行与目录行两态）/ 同段名
    // 子文件夹（含空目录段名）/ 目标位置已是物理目录（探测兜底）
    const targetClashes: WorkspaceFileRow[] =
      await queryWorkspaceFilesByName(db, toDir, name);
    const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    const clashOther: boolean = targetClashes.some((row: WorkspaceFileRow): boolean =>
      row.id !== selfId);
    if (clashOther || dirChildSegments(allRows, toDir).indexOf(name) >= 0 ||
      physicalWorkspaceDirExists(toDirAbs + '/' + name)) {
      return entryOpFailed('目标目录里已有同名文件或文件夹，移动会覆盖它，已取消。请先处理目标里的同名项。');
    }
    if (loc.state === 'file' && loc.fileRow !== undefined) {
      const row: WorkspaceFileRow = loc.fileRow;
      const srcAbs: string = filesDir + '/' + WORKSPACE_DIR_NAME +
        (dir === '' ? '' : '/' + dir) + '/' +
        row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
      const destAbs: string = toDirAbs + '/' +
        row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
      try {
        fs.renameSync(srcAbs, destAbs);
      } catch (e) {
        return entryOpFailed('文件移动失败：' + (e as Error).message);
      }
      const bucket: relationalStore.ValuesBucket = { 'dir': toDir,
        'localPath': relativeWorkspacePath(toDir,
          row.localPath.substring(row.localPath.lastIndexOf('/') + 1)),
        'updatedAt': now };
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('workspace_files');
      predicates.equalTo('id', row.id);
      try {
        await db.update(bucket, predicates);
      } catch (e) {
        try {
          fs.renameSync(destAbs, srcAbs);
        } catch {
          // 回滚也失败：对账自愈兜底
        }
        return entryOpFailed('工作区记录更新失败：' + (e as Error).message);
      }
      return { ok: true, errorText: '', isDir: false, alreadyExists: false, fileCount: 0,
        totalBytes: 0 };
    }
    // 文件夹移动：物理整树搬 + 目录行自身 dir/localPath 更新 + 后代行 dir 前缀重写（后代
    // localPath 重写分流同 rename；无行空目录探测态 = dirRow 缺省零行更新）
    const descendants: WorkspaceFileRow[] = loc.descendants ?? [];
    const childNewPath: string = joinDirName(toDir, name);
    const srcParentAbs: string = filesDir + '/' + WORKSPACE_DIR_NAME +
      (dir === '' ? '' : '/' + dir);
    try {
      fs.renameSync(srcParentAbs + '/' + name, toDirAbs + '/' + name);
    } catch (e) {
      return entryOpFailed('文件夹移动失败：' + (e as Error).message);
    }
    try {
      if (loc.dirRow !== undefined) {
        // 跨层移动的目录行落目标层底（max+1——进新层的可见位置与新建同口径）；同层内
        // toDir === dir 不写序（无层变化，拖拽自定义序保持原位）
        const bucketSelf: relationalStore.ValuesBucket = { 'dir': toDir,
          'localPath': relativeWorkspacePath(toDir, name), 'updatedAt': now };
        if (toDir !== dir) {
          bucketSelf['sortOrder'] = await nextWorkspaceDirOrder(db, toDir);
        }
        const predSelf: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('workspace_files');
        predSelf.equalTo('id', loc.dirRow.id);
        await db.update(bucketSelf, predSelf);
      }
      for (const row of descendants) {
        const newDir: string = row.dir === childPath ? childNewPath :
          childNewPath + row.dir.substring(childPath.length);
        const tail: string = row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
        const newLocalPath: string = isWorkspaceDirRow(row) ?
          WORKSPACE_DIR_NAME + '/' + newDir : relativeWorkspacePath(newDir, tail);
        const bucket: relationalStore.ValuesBucket = { 'dir': newDir,
          'localPath': newLocalPath, 'updatedAt': now };
        const predicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('workspace_files');
        predicates.equalTo('id', row.id);
        await db.update(bucket, predicates);
      }
    } catch (e) {
      try {
        fs.renameSync(toDirAbs + '/' + name, srcParentAbs + '/' + name);
      } catch {
        // 回滚也失败：对账自愈兜底
      }
      return entryOpFailed('工作区记录更新失败：' + (e as Error).message);
    }
    return { ok: true, errorText: '', isDir: true, alreadyExists: false, fileCount: 0,
      totalBytes: 0 };
  });
}

// 删除文件或整个文件夹（delete 工具动作壳；确认链预检在 ToolWorkspace 侧）：文件 = 照既有
// 删链（先删行收集路径 → best-effort 删文件）；文件夹 = 后代行删 + 物理子树后序递归删；
// 删前统计（件数/合计）由本函数算好供执行器组回执
export function deleteWorkspaceEntry(db: relationalStore.RdbStore, dir: string,
  name: string): Promise<WorkspaceEntryOpOutcome> {
  return runWriteQueued('deleteWorkspaceEntry', async (): Promise<WorkspaceEntryOpOutcome> => {
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return entryOpFailed(dirReject);
    }
    const nameReject: string = workspaceNameRejectReason(name);
    if (nameReject !== '') {
      return entryOpFailed(nameReject);
    }
    const loc: EntryLocation = await locateWorkspaceEntry(db, dir, name);
    if (loc.state === 'none') {
      return entryOpFailed('工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
        '没有名为「' + name + '」的文件或文件夹。请先用 workspace_list 查看该目录的内容。');
    }
    if (loc.state === 'amb') {
      return entryOpFailed('该位置存在同名的文件与文件夹，无法确定要删除哪一个。请先在管理页处理或分开删除。');
    }
    if (loc.state === 'file' && loc.fileRow !== undefined) {
      const row: WorkspaceFileRow = loc.fileRow;
      const paths: string[] = await deleteWorkspaceRowsByIds(db, [row.id]);
      removeWorkspaceFiles(paths);
      return { ok: true, errorText: '', isDir: false, alreadyExists: false, fileCount: 0,
        totalBytes: 0 };
    }
    // 文件夹：删前统计 → 删行（目录行自身 + 后代行——子目录行天然在后代集；无行空目录
    // 探测态 = dirRow 缺省、ids 可为空 → deleteWorkspaceRowsByIds 空集短路）→ 物理子树
    // 整删（空子目录无行也一并清）。件数与合计只数**文件行**（目录行 size=0 且不计件数）
    const descendants: WorkspaceFileRow[] = loc.descendants ?? [];
    let totalBytes = 0;
    let fileCount = 0;
    const ids: string[] = [];
    for (const row of descendants) {
      if (!isWorkspaceDirRow(row)) {
        totalBytes += row.size;
        fileCount++;
      }
      ids.push(row.id);
    }
    if (loc.dirRow !== undefined) {
      ids.push(loc.dirRow.id);
    }
    await deleteWorkspaceRowsByIds(db, ids);
    const filesDir: string = workspaceFilesDir();
    if (filesDir !== '') {
      const childPath: string = joinDirName(dir, name);
      removeWorkspaceTree(filesDir + '/' + WORKSPACE_DIR_NAME + '/' + childPath);
    }
    return { ok: true, errorText: '', isDir: true, alreadyExists: false,
      fileCount: fileCount, totalBytes: totalBytes };
  });
}
