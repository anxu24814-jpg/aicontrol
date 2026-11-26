// 工作区存储域：workspace_files 表（v50）行读写 + 文件 IO（写 / 删 / 清空目录树 / uri 拷入）
// + 启动对账（reconcileWorkspace——磁盘为事实源）+ ctx 捕获 + 目录排序消费点。
// · 依赖方向红线（照 AttachmentDb 同款三条）：①本文件不 import ChatDb——store 句柄由调用方
//   传入（ChatDb → WorkspaceDb → WorkspaceUtil 单向，防环）；②页面与工具域一律经 ChatDb 委托
//   入口消费（不导出给 UI，防页面直碰 store 私有）；③文件 IO 的目录前缀经自持 ctx 捕获
//   （initWorkspaceStore——EntryAbility onCreate 调一次）。
// · 生命周期（与附件域核心分叉——工作区是跨会话持久资产）：删会话/删助手**零级联**
//   （conversationId / ownerAssistantId 仅追溯，照 memories 表先例）；不进备份（EXPORT_TABLES
//   零改动）；参与启动对账（行有文件无删行、文件有行无补录；与附件域对账互不干扰——本对账
//   只扫 workspace 目录、collectOrphanFiles 只扫 attachments，注释双向写明防后人合并两链）。
// · 写序铁律：**先落文件 → 后写行**；行写失败自清刚写文件＋中文报错。删序：先删行（收集
//   localPath）→ 删文件 best-effort（文件不存在 = 目标状态）。目录 rename/move = 先物理后行
//   + 失败回滚物理 + 启动对账自愈三重兜底（RDB 无跨文件系统事务，「原子序」= 可恢复排序
//   而非真事务，如实申报）。
// · 并发防线：saveWorkspaceTextFile / saveDownloadToWorkspace / importAttachmentToWorkspace
//   与目录四操作（拆分件 WorkspaceDbEntries / WorkspaceDbManage）、启动对账的「查配额 → 写」
//   /「行删文件清」整段经 DbWriteQueue.runWriteQueued 排队（并发写时配额判定不穿窗——全局
//   写串行链纪律）。
// · 目录行口径：kind='dir' 行 = 文件夹一等行（一行 = 一个文件或一个文件夹）——mkdir 显式
//   铸造 / write·import 隐式铸造（dir 全前缀段）/ 对账登记三路入账；统计与三闸件数口径排除
//   目录行；定位面 (dir, name) 命中目录行 = 文件夹态（空亦可删/改名/移动），未命中态物理探测
//   兜底；创建面三层把守 = 逐段检查（workspaceDirChainReject）+ 目标名行级查重
//   （dirChildSegments——空目录段名天然在场）+ 物理探测兜底（拦对账未完成窗口）。mkdir 随
//   铸造**入写链**（原「纯 fs 不入链」口径废止）。
// · 目录四操作域已外迁拆分件 WorkspaceDbEntries.ets（该件单向 import 本件；本件曾 1269 行越
//   1200 硬线）；ensureWorkspaceDir 与 dirChildSegments 留本件（assert-tool-domain 直读其 export）。
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { WorkspaceFileRow, buildWorkspaceRow, buildWorkspaceDirRow, isWorkspaceDirRow,
  classifyWorkspaceName, dedupeWorkspaceName,
  extOfWorkspaceName, relativeWorkspacePath, workspaceFileName, workspaceDirChainReject,
  workspaceDirRejectReason, workspaceMimeOf, workspaceNameRejectReason,
  sanitizeWorkspaceName, workspaceWriteGateReason, joinDirName,
  WORKSPACE_DIR_NAME, WORKSPACE_KIND_DIR, WORKSPACE_ROWS_READ_MAX,
  WORKSPACE_SOURCE_ASSISTANT, WORKSPACE_SOURCE_RECOVERED } from '../WorkspaceUtil';
// 覆盖注记判据单源在 WorkspaceReply（拆分笔自本件外迁）
import { workspaceOverwriteKindOf } from '../WorkspaceReply';
import { runWriteQueued } from './DbWriteQueue';
// 目录排序域拆分件（依赖方向本件 → WorkspaceDbDirOrder → WorkspaceUtil 单向无环；本件三写点
// 消费其 nextWorkspaceDirOrder，saveWorkspaceDirOrder 由 ChatDb 直引拆分件委托）
import { nextWorkspaceDirOrder } from './WorkspaceDbDirOrder';

const DOMAIN: number = 0xDA4A;
const TAG: string = 'WorkspaceDb';

// 模块级 ctx 捕获（initWorkspaceStore——EntryAbility onCreate 调一次）：写文件 / 删文件 /
// 目录就绪等无 ctx 入参的文件操作用（localPath 是相对 filesDir 路径，拼绝对路径须 ctx）
let workspaceCtx: common.UIAbilityContext | null = null;

// 工作区合计（管理页统计行与三闸判定共用）
export interface WorkspaceTotalRow {
  count: number;
  bytes: number;
}

// 保存结果（闸拒绝 / 多命中防线 / IO 失败的中文原因都走 errorText——P0-1 禁静默）
export interface WorkspaceSaveOutcome {
  ok: boolean;
  errorText: string;
  sizeBytes: number; // ok=true：本次写入的字节数
  totalCount: number; // ok=true：保存后的工作区件数
  displayName: string; // ok=true：实际落库显示名（= sanitize 清洗后的名）——写回执按它报，
  // 防「回执名 ≠ 列表名」漂移（清洗可改名，回执若回用原始入参名，模型随后按回执名 read 必失败）；
  // 失败态恒 ''
  // ★ 跨会话覆盖提醒：覆盖路命中非本会话归属时的注记档（判据单源 workspaceOverwriteKindOf
  // ——'conversation' 他会话 / 'external' 上传与恢复件）；新建路与各失败态缺省 undefined，
  // 回执按「空串不注记」消费（write 与 write_xlsx 两路经本字段，import 路见 HttpBinary.ImportOutcome）
  overwriteKind?: string;
}

// ctx 捕获（照 initAttachmentStore 先例；先于任何工作区文件操作）
export function initWorkspaceStore(ctx: common.UIAbilityContext): void {
  workspaceCtx = ctx;
}

// 捕获 ctx 的 filesDir 读出口（照 attachmentFilesDir 先例；未捕获回 ''——消费方按
// 「无路径信息不删文件」处理）
export function workspaceFilesDir(): string {
  return workspaceCtx !== null ? workspaceCtx.filesDir : '';
}

// 捕获 ctx 的 cacheDir 读出口（xlsx 写出核的临时产物目录——系统可回收区，不占用户数据语义；
// 未捕获回 ''——调用方按「目录未就绪」中文报错）
export function workspaceCacheDir(): string {
  return workspaceCtx !== null ? workspaceCtx.cacheDir : '';
}

// 目录就绪（返回绝对路径；EEXIST = 目标状态静默；ctx 未捕获抛中文错——P0-1）
// ★ HttpBinary 下载/导入两 I/O 壳可为首次工作区操作——不先行建目录则 openSync 抛 ENOENT，
// 故导出本函数供其先行调用，目录铸造单源仍在本件。relDir 缺省 '' = 根；recursion=true 天然
// mkdir -p；入口对 relDir 复跑目录闸（防新调用点漏闸的双保险），.. \ \0 与空段零容忍
export function ensureWorkspaceDir(relDir: string = ''): string {
  if (workspaceCtx === null) {
    throw new Error('工作区目录未就绪，无法保存文件');
  }
  if (relDir !== '') {
    const reject: string = workspaceDirRejectReason(relDir);
    if (reject !== '') {
      throw new Error(reject);
    }
  }
  const dir: string = workspaceCtx.filesDir + '/' + WORKSPACE_DIR_NAME +
    (relDir === '' ? '' : '/' + relDir);
  try {
    fs.mkdirSync(dir, true);
  } catch (e) {
    const err = e as BusinessError;
    if (err.code !== 13900015) {
      throw e as Error;
    }
  }
  return dir;
}

// ── 查询面（带 db 参数形态——照 AttachmentDb；句柄由 ChatDb 委托层传入）──
// 全量列表（上限由调用方传入——一律传 WORKSPACE_ROWS_READ_MAX：行集 = 文件行 ≤
// WORKSPACE_MAX_COUNT + 目录行，严禁回退件数常量，否则行总数越 1000 即截断）。带 LIMIT ⇒
// ORDER BY 即**成员集判据**（坑69/70 切序红线），切序会改变截断面成员——目录自定义序消费面在
// deriveWorkspaceDirListing 内存段，本查询只加投影列 sortOrder，成员集逐字节一致
export async function queryWorkspaceFiles(db: relationalStore.RdbStore,
  limit: number): Promise<WorkspaceFileRow[]> {
  if (limit <= 0) {
    return [];
  }
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, name, dir, kind, mime, size, localPath, source, conversationId, ownerAssistantId, ' +
    'createdAt, updatedAt, sortOrder FROM workspace_files ORDER BY updatedAt DESC LIMIT ?', [limit]);
  const rows: WorkspaceFileRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        dir: result.getString(result.getColumnIndex('dir')),
        kind: result.getString(result.getColumnIndex('kind')),
        mime: result.getString(result.getColumnIndex('mime')),
        size: result.getLong(result.getColumnIndex('size')),
        localPath: result.getString(result.getColumnIndex('localPath')),
        source: result.getString(result.getColumnIndex('source')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        ownerAssistantId: result.getString(result.getColumnIndex('ownerAssistantId')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
        sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// 合计（一行聚合，管理页统计与三闸共用；★ 目录行笔：排除目录行——文件夹不计件数不占
// 容量，三闸件数口径随之为纯文件件数）
export async function queryWorkspaceTotal(db: relationalStore.RdbStore):
  Promise<WorkspaceTotalRow> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT COUNT(*) AS cnt, IFNULL(SUM(size), 0) AS bytes FROM workspace_files ' +
    'WHERE kind != ?', [WORKSPACE_KIND_DIR]);
  const total: WorkspaceTotalRow = { count: 0, bytes: 0 };
  try {
    if (result.goToNextRow()) {
      total.count = result.getLong(result.getColumnIndex('cnt'));
      total.bytes = result.getLong(result.getColumnIndex('bytes'));
    }
  } finally {
    result.close();
  }
  return total;
}

// 按 (dir, name) 精确匹配（write 覆盖判定与 read 定位；name 目录内唯一、跨目录可同名——
// 文件夹笔起显示名全局唯一假设废止，定位恒二元组；多命中 = 异常数据，调用方须防线报错）
export async function queryWorkspaceFilesByName(db: relationalStore.RdbStore,
  dir: string, name: string): Promise<WorkspaceFileRow[]> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT id, name, dir, kind, mime, size, localPath, source, conversationId, ownerAssistantId, ' +
    'createdAt, updatedAt, sortOrder FROM workspace_files WHERE dir = ? AND name = ? ORDER BY rowid',
    [dir, name]);
  const rows: WorkspaceFileRow[] = [];
  try {
    while (result.goToNextRow()) {
      rows.push({
        id: result.getString(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        dir: result.getString(result.getColumnIndex('dir')),
        kind: result.getString(result.getColumnIndex('kind')),
        mime: result.getString(result.getColumnIndex('mime')),
        size: result.getLong(result.getColumnIndex('size')),
        localPath: result.getString(result.getColumnIndex('localPath')),
        source: result.getString(result.getColumnIndex('source')),
        conversationId: result.getString(result.getColumnIndex('conversationId')),
        ownerAssistantId: result.getString(result.getColumnIndex('ownerAssistantId')),
        createdAt: result.getLong(result.getColumnIndex('createdAt')),
        updatedAt: result.getLong(result.getColumnIndex('updatedAt')),
        sortOrder: result.getLong(result.getColumnIndex('sortOrder'))
      });
    }
  } finally {
    result.close();
  }
  return rows;
}

// ── 删除面（笔 2 管理页消费；域件随笔 1 一次落全——先删行收集路径、后删文件）──
// 按 id 删行（返回相对路径集供 commit 后删文件；空集短路——in() 空数组条件失效落全表）
export async function deleteWorkspaceRowsByIds(db: relationalStore.RdbStore,
  ids: string[]): Promise<string[]> {
  if (ids.length === 0) {
    return [];
  }
  const predicates: relationalStore.RdbPredicates =
    new relationalStore.RdbPredicates('workspace_files');
  predicates.in('id', ids);
  const paths: string[] = [];
  const result: relationalStore.ResultSet = await db.query(predicates, ['localPath']);
  try {
    while (result.goToNextRow()) {
      paths.push(result.getString(result.getColumnIndex('localPath')));
    }
  } finally {
    result.close();
  }
  await db.delete(predicates);
  return paths;
}

// 全表删行（清空工作区；返回路径集同上）
export async function clearWorkspaceRows(db: relationalStore.RdbStore):
  Promise<string[]> {
  const paths: string[] = [];
  const result: relationalStore.ResultSet =
    await db.querySql('SELECT localPath FROM workspace_files');
  try {
    while (result.goToNextRow()) {
      paths.push(result.getString(result.getColumnIndex('localPath')));
    }
  } finally {
    result.close();
  }
  await db.executeSql('DELETE FROM workspace_files');
  return paths;
}

// 按相对路径集删工作区文件（best-effort——文件不存在 = 目标状态；ctx 未捕获 warn 跳过）
export function removeWorkspaceFiles(paths: string[]): void {
  if (workspaceCtx === null) {
    hilog.warn(DOMAIN, TAG, '工作区 ctx 未捕获（initWorkspaceStore 未调用），跳过文件删除');
    return;
  }
  for (const p of paths) {
    try {
      fs.unlinkSync(workspaceCtx.filesDir + '/' + p);
    } catch {
      // 文件不存在 = 目标状态，静默
    }
  }
}

// 递归删树（后序遍历自实现——官方 rmdirSync 删非空目录抛 13900032，本 SDK ets API 面**无
// fs.rmSync**〔本地 d.ts 实核〕，勿赌官方递归删）：文件 unlink、子目录先删内容再 rmdir；
// 单件失败跳过继续（有界自愈——下次清空/对账再删）。临时区 WorkspaceDbTmp 复用同款递归删
export function removeWorkspaceTree(absDir: string): void {
  let names: string[] = [];
  try {
    names = fs.listFileSync(absDir);
  } catch {
    return; // 目录不存在 = 目标状态
  }
  for (const name of names) {
    const child: string = absDir + '/' + name;
    try {
      if (fs.statSync(child).isDirectory()) {
        removeWorkspaceTree(child);
      } else {
        fs.unlinkSync(child);
      }
    } catch {
      // 单件失败跳过——下次清空/对账再删（有界自愈）
    }
  }
  try {
    fs.rmdirSync(absDir);
  } catch {
    // 根目录本体删不掉（仍有存活句柄等）跳过——内容已尽力清
  }
}

// 清空整个目录内容（清空工作区兜底：不止删行内文件，孤儿残留一并覆盖；目录不存在 =
// 目标状态）——顶层逐项分流：文件 unlink / 子目录走 removeWorkspaceTree 整树删
export function clearWorkspaceDirContents(): void {
  if (workspaceCtx === null) {
    hilog.warn(DOMAIN, TAG, '工作区 ctx 未捕获，跳过目录清空');
    return;
  }
  const dir: string = workspaceCtx.filesDir + '/' + WORKSPACE_DIR_NAME;
  try {
    const names: string[] = fs.listFileSync(dir);
    for (const name of names) {
      const child: string = dir + '/' + name;
      try {
        if (fs.statSync(child).isDirectory()) {
          removeWorkspaceTree(child);
        } else {
          fs.unlinkSync(child);
        }
      } catch {
        // 单文件失败跳过——下次清空再删（有界自愈）
      }
    }
  } catch {
    // 目录不存在 = 干净，目标状态
  }
}

// ── 文件 IO 面 ──
// 文本写入（新建 / 覆写共用；truncate = 覆写——content 长短可变，不 TRUNC 会留旧尾巴；
// writeSync 只吃 string——d.ts 实锤）。WorkspaceDbEdit 编辑编排复用本口（truncate 路写回原文件）
export function writeWorkspaceText(absPath: string, content: string, truncate: boolean): void {
  const mode: number = truncate ?
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC :
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE;
  const file: fs.File = fs.openSync(absPath, mode);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
}

// 读文本（read 工具消费；读失败抛中文错由调用方转回执）
export function readWorkspaceFileText(absPath: string): string {
  try {
    return fs.readTextSync(absPath);
  } catch (e) {
    throw new Error('文件读取失败：' + (e as Error).message);
  }
}

// 工作区文件原始字节 → base64（PDF 原件直传唯一消费方）。短读守卫照 DocumentParse.readBase64
//——readSync 返回值 < buffer 长时必须 slice 再编码，否则零填充尾部混入 base64。错误形态
//（与 ToolWorkspace doc 路原生分支口径一致）：全包 try/catch 恒不抛错——读失败 / 空文件 /
// stat 失败一律返回 ''（空串 = 本次不可用，调用方据此放弃原生路回落解析路，不新增错误文案面）
export function readWorkspaceFileBase64(absPath: string): string {
  try {
    const stat: fs.Stat = fs.statSync(absPath);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    const file: fs.File = fs.openSync(absPath, fs.OpenMode.READ_ONLY);
    try {
      const len: number = fs.readSync(file.fd, buf);
      const data: ArrayBuffer = len === buf.byteLength ? buf : buf.slice(0, len);
      return new util.Base64Helper().encodeToStringSync(new Uint8Array(data));
    } finally {
      fs.closeSync(file);
    }
  } catch {
    return '';
  }
}

// picker uri 拷入工作区（上传链消费；三步 fd 法照 copyAttachmentResource 姿势——picker
// 返回 uri 是临时授权，必须拷进沙箱再长期使用）：返回新文件相对路径。dir 缺省 '' = 根 =
// 既有调用零改动——上传落当前打开的文件夹，目录经 ensureWorkspaceDir(relDir) 隐式创建
//（含全中间层）。失败自清半截目标 + 上抛（P0-1）
export function copyUriIntoWorkspace(uri: string, fileId: string, ext: string,
  dir: string = ''): string {
  if (workspaceCtx === null) {
    throw new Error('工作区目录未就绪，无法上传文件');
  }
  ensureWorkspaceDir(dir);
  const newRel: string = relativeWorkspacePath(dir, workspaceFileName(fileId, ext));
  const destAbs: string = workspaceCtx.filesDir + '/' + newRel;
  const srcFile: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const destFile: fs.File = fs.openSync(destAbs,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      fs.copyFileSync(srcFile.fd, destFile.fd);
    } finally {
      fs.closeSync(destFile);
    }
  } catch (e) {
    try {
      fs.unlinkSync(destAbs);
    } catch {
      // 删不掉留残留：「清空工作区」清整个目录兜底，不吞原始错误
    }
    throw e as Error;
  } finally {
    fs.closeSync(srcFile);
  }
  return newRel;
}

// ── 保存编排（write 工具唯一写口；上传走 copyUriIntoWorkspace + insertWorkspaceRow）──
// 全流程（★ 2026-10-02 文件夹笔加末参 dir，缺省 '' = 根 = 既有调用零改动）：dir 闸 →
// 名称闸 → 清洗 → (dir, name) 查重 → 子文件夹段名冲突检查 → 查合计 → 三闸 → 目录隐式
// 创建 → 写文件 → 写行（失败自清）。查写两段经 runWriteQueued 排队（并发 write 的配额
// 判定不穿窗）。同 dir 同 name 命中 = 覆盖（跨目录同名各存一份不互扰）
export function saveWorkspaceTextFile(db: relationalStore.RdbStore, rawName: string,
  content: string, source: string, conversationId: string,
  ownerAssistantId: string, dir: string = ''): Promise<WorkspaceSaveOutcome> {
  return runWriteQueued('saveWorkspaceText', async (): Promise<WorkspaceSaveOutcome> => {
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return { ok: false, errorText: dirReject, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const reject: string = workspaceNameRejectReason(rawName);
    if (reject !== '') {
      return { ok: false, errorText: reject, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const displayName: string = sanitizeWorkspaceName(rawName);
    // 空串短路（★ 2026-10-04 修复笔：本地 d.ts 明示 encodeInto 空串入参返回 undefined——
    // 读 .length 即 TypeError；空内容建空文件是 write 合法路径，字节长恒 0）
    const byteLen: number = content === '' ? 0 :
      util.TextEncoder.create('utf-8').encodeInto(content).length;
    // 同名匹配（write 覆盖策略：唯一命中覆盖 / 零命中新建 / 多命中防线报错）
    const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(db, dir, displayName);
    if (matches.length > 1) {
      return { ok: false,
        errorText: '工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') + '存在多个名为「' +
          displayName + '」的文件（数据异常），无法保存。请用户在 设置 → 文件工作区 中删除重复文件。',
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const existing: WorkspaceFileRow | undefined = matches.length === 1 ? matches[0] : undefined;
    // 子文件夹段名冲突 + 目录链逐段检查（目标名撞 dir 下子文件夹段名拒〔子段名集改读目录行
    //——空目录段名天然在场，文件行前缀派生兜底〕+ dir 前缀段撞文件行拒；全表一次查两检查
    // 共用，禁 SQL LIKE〔dir 段合法含 % _，通配注入面〕）
    const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    if (dirChildSegments(allRows, dir).indexOf(displayName) >= 0) {
      return { ok: false,
        errorText: '该位置已有同名文件夹，请换一个名称或先删除该文件夹。',
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const chainReject: string = workspaceDirChainReject(allRows, dir);
    if (chainReject !== '') {
      return { ok: false, errorText: chainReject, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    // 物理探测兜底（§8-15 修订③——对账未完成窗口目标位置已是物理目录也拒，防落行后对账
    // 补登记目录行成二义态）
    if (workspaceCtx !== null && physicalWorkspaceDirExists(workspaceCtx.filesDir + '/' +
      relativeWorkspacePath(dir, displayName))) {
      return { ok: false,
        errorText: '该位置已有同名文件夹，请换一个名称或先删除该文件夹。',
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const total: WorkspaceTotalRow = await queryWorkspaceTotal(db);
    // 三闸口径：覆盖路不占新件数（count 判定按既有行放行），总量按折算（现总量 − 旧 size
    // + 新 size 与上限比较——capacity 闸以「不超限」入参表达，故减去旧 size 后让闸加新值）
    const gateReason: string = existing !== undefined ?
      workspaceWriteGateReason(byteLen, total.count - 1, total.bytes - existing.size) :
      workspaceWriteGateReason(byteLen, total.count, total.bytes);
    if (gateReason !== '') {
      return { ok: false, errorText: gateReason, sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const dirAbs: string = ensureWorkspaceDir(dir);
    // 目录行铸造（隐式建目录的入账面——dir 全前缀段，闸已在上方把守；此处的文件行撞名
    // throw 为防御面（写链内无并发，理论不可达），中文上抛不自清已建目录〔目录行残留由
    // 对账登记语义消化——物理在行在〕）
    try {
      await ensureWorkspaceDirRows(db, dir, source, conversationId, ownerAssistantId);
    } catch (e) {
      return { ok: false, errorText: (e as Error).message,
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    if (existing !== undefined) {
      // 覆盖：保留 id 与路径（显示名相同 → ext 相同 → 物理名相同），更新 size/updatedAt；
      // 绝对路径从 ensureWorkspaceDir 的返回值派生（localPath 尾段 = 物理文件名）
      const absPath: string = dirAbs + '/' +
        existing.localPath.substring(existing.localPath.lastIndexOf('/') + 1);
      try {
        writeWorkspaceText(absPath, content, true);
      } catch (e) {
        return { ok: false, errorText: '文件写入失败：' + (e as Error).message,
          sizeBytes: 0, totalCount: 0, displayName: '' };
      }
      const bucket: relationalStore.ValuesBucket = {
        'size': byteLen, 'updatedAt': Date.now() };
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('workspace_files');
      predicates.equalTo('id', existing.id);
      try {
        await db.update(bucket, predicates);
      } catch (e) {
        // 覆盖路不自清文件——旧文件本就有主（旧行仍在），清了会把用户旧文件毁掉；库行与
        // 文件的不一致由用户重试保存收敛（行写失败是罕见异常面）
        return { ok: false, errorText: '工作区记录更新失败：' + (e as Error).message,
          sizeBytes: 0, totalCount: 0, displayName: '' };
      }
      return { ok: true, errorText: '', sizeBytes: byteLen, totalCount: total.count,
        displayName: displayName,
        // 覆盖注记档（★ 2026-10-03 跨会话覆盖提醒笔）：判据只在这条覆盖成功返回段置位
        overwriteKind:
          workspaceOverwriteKindOf(existing.conversationId, conversationId) };
    }
    // 新建：铸 fileId → 先落文件 → 后写行（行写失败自清刚写文件）
    const fileId: string = util.generateRandomUUID(true);
    const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, byteLen,
      source, conversationId, ownerAssistantId, Date.now(), 'text', dir);
    const absPath: string = dirAbs + '/' +
      workspaceFileName(fileId, extOfWorkspaceName(displayName));
    try {
      writeWorkspaceText(absPath, content, false);
    } catch (e) {
      return { ok: false, errorText: '文件写入失败：' + (e as Error).message,
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    const bucket: relationalStore.ValuesBucket = {
      'id': row.id, 'name': row.name, 'dir': row.dir, 'kind': row.kind, 'mime': row.mime,
      'size': row.size, 'localPath': row.localPath, 'source': row.source,
      'conversationId': row.conversationId, 'ownerAssistantId': row.ownerAssistantId,
      'createdAt': row.createdAt, 'updatedAt': row.updatedAt, 'sortOrder': row.sortOrder };
    try {
      await db.insert('workspace_files', bucket);
    } catch (e) {
      try {
        fs.unlinkSync(absPath);
      } catch {
        // 自清失败留残留：「清空工作区」清整个目录兜底，不吞原始错误
      }
      return { ok: false, errorText: '工作区记录写入失败：' + (e as Error).message,
        sizeBytes: 0, totalCount: 0, displayName: '' };
    }
    return { ok: true, errorText: '', sizeBytes: byteLen, totalCount: total.count + 1,
      displayName: displayName };
  });
}

// dir 下直接子文件夹段名集（改读目录行：kind='dir' 且父目录 = dir——空目录段名天然在场；
// 文件行前缀派生保留为并集兜底〔对账未完成窗口目录行未补时查重不缺段名〕。startsWith
// 前缀比较，禁 SQL LIKE——dir 段合法含 % _ 通配注入面）。导出供 HttpBinary 导入壳复用同款
// 判据——import 路原缺本检查，附件名撞既有文件夹即静默产生「同名文件 × 文件夹」二义态
export function dirChildSegments(rows: WorkspaceFileRow[], dir: string): string[] {
  const prefix: string = dir === '' ? '' : dir + '/';
  const segs: string[] = [];
  for (const row of rows) {
    if (isWorkspaceDirRow(row)) {
      if (row.dir === dir && segs.indexOf(row.name) < 0) {
        segs.push(row.name);
      }
      continue;
    }
    if (row.dir !== dir && row.dir.startsWith(prefix)) {
      const rest: string = row.dir.substring(prefix.length);
      const seg: string = rest.split('/')[0];
      if (seg !== '' && segs.indexOf(seg) < 0) {
        segs.push(seg);
      }
    }
  }
  return segs;
}

// 物理目录在场判定（accessSync + statSync.isDirectory——文件在场不算；探测兜底单源：mkdir
// 幂等 / 创建面目标探测 / locate 未命中态探测 / move 目标目录检查共用；导出供 HttpBinary
// 导入壳与 ToolWorkspace 预检复用——providers → store 既有合法依赖方向）
export function physicalWorkspaceDirExists(absDir: string): boolean {
  try {
    return fs.accessSync(absDir) && fs.statSync(absDir).isDirectory();
  } catch {
    return false;
  }
}

// 目录行铸造（三路入账的执行面）：dir 全前缀段各铸一行（含隐式中间层）；段已有行（目录行
// = 已入账跳过，不刷 updatedAt——避免每次 write 翻祖先时间戳；文件行 = 调用方闸漏的防御面，
// 抛中文错——P0-1 禁静默）。**须在写链内调用**（DB 写）；导出供 HttpBinary 导入壳复用
export async function ensureWorkspaceDirRows(db: relationalStore.RdbStore, dir: string,
  source: string, conversationId: string, ownerAssistantId: string): Promise<void> {
  if (dir === '') {
    return;
  }
  const segs: string[] = dir.split('/');
  let parent: string = '';
  const now: number = Date.now();
  for (const seg of segs) {
    const hits: WorkspaceFileRow[] = await queryWorkspaceFilesByName(db, parent, seg);
    let exists = false;
    for (const row of hits) {
      if (isWorkspaceDirRow(row)) {
        exists = true;
      } else {
        throw new Error('目录路径「' + dir + '」无法使用，其中「' + seg +
          '」与所在位置的文件同名。请换一个目录路径，或先处理同名文件。');
      }
    }
    if (!exists) {
      const row: WorkspaceFileRow = buildWorkspaceDirRow(util.generateRandomUUID(true),
        seg, parent, source, conversationId, ownerAssistantId, now);
      // v50：新铸目录行落父层底（max+1——排序域判据见 nextWorkspaceDirOrder；纯函数构建
      // 缺省 0，铸造点回填）
      row.sortOrder = await nextWorkspaceDirOrder(db, parent);
      await insertWorkspaceRow(db, row);
    }
    parent = parent === '' ? seg : parent + '/' + seg;
  }
}

// 上传行直插（笔 2 上传链消费：copyUriIntoWorkspace 落文件后入行；source='user'，
// conversationId / ownerAssistantId 恒空串——管理页上传无会话上下文）
export async function insertWorkspaceRow(db: relationalStore.RdbStore,
  row: WorkspaceFileRow): Promise<void> {
  const bucket: relationalStore.ValuesBucket = {
    'id': row.id, 'name': row.name, 'dir': row.dir, 'kind': row.kind, 'mime': row.mime,
    'size': row.size, 'localPath': row.localPath, 'source': row.source,
    'conversationId': row.conversationId, 'ownerAssistantId': row.ownerAssistantId,
    'createdAt': row.createdAt, 'updatedAt': row.updatedAt, 'sortOrder': row.sortOrder };
  await db.insert('workspace_files', bucket);
}

// 行 upsert（导入覆盖路与下载路消费：按 id REPLACE——覆盖〔同名唯一命中，沿用既有 id 与
// 追溯列〕与新建统一走本口；「先落文件 → 后写行、行写失败自清」铁律由调用方保证。REPLACE
// 整行覆盖 sortOrder 随 row 写入——本口只服务文件行〔目录行无下载/导入路〕，覆 0 无行为面）
export async function upsertWorkspaceRow(db: relationalStore.RdbStore,
  row: WorkspaceFileRow): Promise<void> {
  await db.executeSql(
    'INSERT OR REPLACE INTO workspace_files (id, name, dir, kind, mime, size, localPath, source, ' +
    'conversationId, ownerAssistantId, createdAt, updatedAt, sortOrder) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
    [row.id, row.name, row.dir, row.kind, row.mime, row.size, row.localPath, row.source,
      row.conversationId, row.ownerAssistantId, row.createdAt, row.updatedAt, row.sortOrder]);
}

// 挂载文件拷入工作区（mount_copy_out 与 browse_screenshot 共用落库口；闸链镜像
// saveWorkspaceTextFile / HttpBinary.importAttachmentToWorkspace 的「dir 闸 → 名称闸 → 清洗
// → (dir, name) 查重 → 创建面三层把守 → 容量闸 → 目录隐式创建 → fd 拷贝 → 行 upsert」，
// 差异只在源 = 挂载内文件绝对路径〔执行器已激活授权并转路径〕。同值 30MB 单件上限与
// HttpBinary.WORKSPACE_IMPORT_MAX_BYTES 镜像同源——WorkspaceDb 不 import HttpBinary〔反向
// 即环〕，同值关系由 assert-mount-domain 钉住）。source 缺省 'assistant' = 工具面 AI 复制；
// 用户面（浏览页「复制到工作区」）传 'user'——归属两列恒空串，与管理页上传行形同构（来源
// 标注显示「我上传」）
export const MOUNT_COPY_IN_MAX_BYTES: number = 30 * 1024 * 1024;

export function mountCopyIntoWorkspace(db: relationalStore.RdbStore, srcAbsPath: string,
  rawName: string, sizeBytes: number, conversationId: string,
  ownerAssistantId: string, dir: string = '',
  source: string = WORKSPACE_SOURCE_ASSISTANT): Promise<WorkspaceSaveOutcome> {
  return runWriteQueued('mountCopyIntoWorkspace', async (): Promise<WorkspaceSaveOutcome> => {
    const failed = (text: string): WorkspaceSaveOutcome =>
      ({ ok: false, errorText: text, sizeBytes: 0, totalCount: 0, displayName: '' });
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return failed(dirReject);
    }
    if (sizeBytes > MOUNT_COPY_IN_MAX_BYTES) {
      return failed('文件超过 ' + (MOUNT_COPY_IN_MAX_BYTES / (1024 * 1024)) +
        'MB 的复制上限，无法存入工作区');
    }
    // 落库名（清洗在此定稿——覆盖判定与行构建用同一份名，两处同源）
    const displayName: string = sanitizeWorkspaceName(rawName);
    // 同名覆盖判定（(dir, name) 二元组；跨目录同名各存一份不互扰）+ 创建面三层把守（与
    // write·import 路同款单源判据，全表一次查两检查共用）
    const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(db, dir, displayName);
    if (matches.length > 1) {
      return failed('工作区' + (dir === '' ? '根目录' : '「' + dir + '」目录') +
        '存在多个名为「' + displayName + '」的文件（数据异常），无法保存');
    }
    const existing: WorkspaceFileRow | undefined = matches.length === 1 ? matches[0] : undefined;
    const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    if (dirChildSegments(allRows, dir).indexOf(displayName) >= 0) {
      return failed('该位置已有同名文件夹，请换一个名称或先删除该文件夹。');
    }
    const chainReject: string = workspaceDirChainReject(allRows, dir);
    if (chainReject !== '') {
      return failed(chainReject);
    }
    if (workspaceCtx !== null && physicalWorkspaceDirExists(workspaceCtx.filesDir + '/' +
      relativeWorkspacePath(dir, displayName))) {
      return failed('该位置已有同名文件夹，请换一个名称或先删除该文件夹。');
    }
    const total: WorkspaceTotalRow = await queryWorkspaceTotal(db);
    // 容量闸口径同 write 路：覆盖路不占新件数，总量按折算（现总量 − 旧 size + 新 size）
    const gateReason: string = existing !== undefined ?
      workspaceWriteGateReason(sizeBytes, total.count - 1, total.bytes - existing.size) :
      workspaceWriteGateReason(sizeBytes, total.count, total.bytes);
    if (gateReason !== '') {
      return failed(gateReason);
    }
    // 目录就绪（隐式创建含 dir 全中间层）+ 目录行铸造（仍在写链内）
    let dirAbs: string = '';
    try {
      dirAbs = ensureWorkspaceDir(dir);
      await ensureWorkspaceDirRows(db, dir, source, conversationId, ownerAssistantId);
    } catch (e) {
      return failed('文件复制失败：' + (e as Error).message);
    }
    // fd 拷贝（镜像 importAttachmentToWorkspace 三步 fd 法；覆盖路物理名可能随扩展名不同
    // 而不同：旧行文件残留由「清空工作区」兜底清，行 localPath 指向新文件为准）
    const fileId: string = existing !== undefined ? existing.id : util.generateRandomUUID(true);
    const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, sizeBytes,
      source, conversationId, ownerAssistantId, Date.now(), 'other', dir);
    const absPath: string = dirAbs + '/' +
      row.localPath.substring(row.localPath.lastIndexOf('/') + 1);
    const src: fs.File = fs.openSync(srcAbsPath, fs.OpenMode.READ_ONLY);
    try {
      const dest: fs.File = fs.openSync(absPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
    } catch (e) {
      if (existing === undefined) {
        try {
          fs.unlinkSync(absPath);
        } catch {
          // 自清失败留残留：「清空工作区」清整个目录兜底，不吞原始错误
        }
      }
      return failed('文件复制失败：' + (e as Error).message);
    } finally {
      fs.closeSync(src);
    }
    try {
      await upsertWorkspaceRow(db, row);
    } catch (e) {
      if (existing === undefined) {
        try {
          fs.unlinkSync(absPath);
        } catch {
          // 同上——best-effort 自清
        }
      }
      return failed('工作区记录写入失败：' + (e as Error).message);
    }
    return { ok: true, errorText: '', sizeBytes: sizeBytes, totalCount: total.count,
      displayName: displayName,
      overwriteKind: existing !== undefined ?
        workspaceOverwriteKindOf(existing.conversationId, conversationId) : undefined };
  });
}

// ── 目录四操作域已外迁：WorkspaceEntryOpOutcome / locateWorkspaceEntry / createWorkspaceDir
//   / renameWorkspaceEntry / moveWorkspaceEntry / deleteWorkspaceEntry 整段迁
//   WorkspaceDbEntries.ets（该件单向 import 本件；ChatDb 四委托口改自新件引）。

// ── 目录排序域（v50）──
// 域级单源在拆分件 WorkspaceDbDirOrder.ets（排序键生成 vs 扫描判据、禁切清单、两原语全在
// 彼件头注释）；本件只承载三处铸造/移动写点对 nextWorkspaceDirOrder 的消费。

// ── 启动对账 ──
// 方向（零数据损失）：行有文件无 → 删行；文件有行无 → 补录（磁盘为事实源——外部塞进来
// 的文件重启后入册标「恢复」，指向已删文件的记录清除）。
// ★ 无 mtime 在途保护闸（与附件域的有意分叉）：附件域 collectOrphanFiles 的 mtime 闸防
// 「已选未发 / 发送中」在途件；工作区写序恒**先文件后行**（文件头铁律），行存在 ⇒ 文件已
// 落定，行指向文件缺失只能是已被删除——无在途窗口；补录方向只增不删无风险。
// ★ 调用面 fire-and-forget 不阻塞首帧（EntryAbility）⇒ 与工具写链存在真实交错窗口
//（「聊一半重启立刻继续写」是保住场景；原「启动时点无并发面」断言废止）——整段入
// runWriteQueued 链节与写链互斥；交错窗口若在历史版本产生过死行（write 落库行指向被补录
// 重铸的旧物理名），由下方死行删自愈。只扫 workspace 目录——附件对账只扫 attachments
//（collectOrphanFiles），两链互不干扰，勿合并
export interface WorkspaceReconcileSummary {
  rowsRemoved: number;
  filesRecovered: number;
  dirsRegistered: number; // ★ 目录行笔：物理目录无行 → 补登记的目录行数
}

interface PhysFileEntry {
  relPath: string; // 相对 filesDir（workspace/<dir段…>/<物理名>）
  dir: string; // 逻辑目录（'' = 根）
  physName: string;
}

export function reconcileWorkspace(db: relationalStore.RdbStore):
  Promise<WorkspaceReconcileSummary> {
  // ★ 整段入全局写串行链——fire-and-forget 不阻塞首帧 ⇒ 与工具写链有真实交错面；只把
  // 写行段入链不彻底（walk 快照在链外采集时可含「文件已落行未写」在途件，链内按旧快照
  // 补录 = 重铸物理名制造死行），walk 与补录/登记/死行删须同节。启动时点链空立即执行
  // 无初始化顺序依赖（DbWriteQueue 头注释）；小目录毫秒级，对排队写零感
  return runWriteQueued('reconcileWorkspace', (): Promise<WorkspaceReconcileSummary> =>
    reconcileWorkspaceInChain(db));
}

// 对账链节体（reconcileWorkspace 入链壳的唯一内层；原函数体逐字未动——链内调用的
// insertWorkspaceRow / deleteWorkspaceRowsByIds / nextWorkspaceDirOrder 全为裸原语，零嵌套）
async function reconcileWorkspaceInChain(db: relationalStore.RdbStore):
  Promise<WorkspaceReconcileSummary> {
  const summary: WorkspaceReconcileSummary = { rowsRemoved: 0, filesRecovered: 0,
    dirsRegistered: 0 };
  if (workspaceCtx === null) {
    hilog.warn(DOMAIN, TAG, '工作区 ctx 未捕获（initWorkspaceStore 未调用），跳过启动对账');
    return summary;
  }
  const filesDir: string = workspaceCtx.filesDir;
  // 只扫 workspace 目录——附件对账只扫 attachments（collectOrphanFiles），两链互不干扰，
  // 勿合并；★ workspace-tmp 为易失区**勿并入对账**（2026-10-03 地基笔——临时区不进表不
  // 对账，扫了会把全部临时件当孤儿补录进 workspace_files）
  const rootAbs: string = filesDir + '/' + WORKSPACE_DIR_NAME;
  const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
  const livePaths: Set<string> = new Set<string>();
  for (const row of rows) {
    livePaths.add(row.localPath);
  }
  // 物理递归遍历（目录不存在 = 干净目标态）：收集全部物理文件 + 每目录直接子文件夹段名
  //（补录避重用）+ 全部物理目录清单（目录行登记的判据面）
  const physFiles: PhysFileEntry[] = [];
  const physDirs: string[] = [];
  const childDirs: Map<string, string[]> = new Map<string, string[]>();
  const walk = (absDir: string, relDir: string): void => {
    let names: string[] = [];
    try {
      names = fs.listFileSync(absDir);
    } catch {
      return; // 目录不存在 = 干净，目标状态
    }
    for (const nm of names) {
      const childAbs: string = absDir + '/' + nm;
      const childRelDir: string = relDir === '' ? nm : relDir + '/' + nm;
      try {
        if (fs.statSync(childAbs).isDirectory()) {
          const list: string[] = childDirs.get(relDir) ?? [];
          list.push(nm);
          childDirs.set(relDir, list);
          physDirs.push(childRelDir);
          walk(childAbs, childRelDir);
        } else {
          physFiles.push({ relPath: WORKSPACE_DIR_NAME + '/' + childRelDir,
            dir: relDir, physName: nm });
        }
      } catch {
        // stat 失败（并发删除等）跳过——下次对账再判
      }
    }
  };
  walk(rootAbs, '');
  // ②补录（文件有行无）：物理名统一重铸 <uuid>.<ext>（红线「物理名恒 UUID 防注入」——
  // 外部文件名任意，直接入 localPath 会破不变量）；displayName = sanitize('恢复_' + 物理名)
  // 后在本目录内 dedupe（避重名单 = 该目录文件显示名 ∪ 该目录子文件夹段名——补录永不
  // 制造 §1.5-1 二义态；已补录的行 push 回 rows 让后续补录的避重自然生效）
  for (const f of physFiles) {
    if (livePaths.has(f.relPath)) {
      continue;
    }
    try {
      const absOld: string = filesDir + '/' + f.relPath;
      const stat: fs.Stat = fs.statSync(absOld);
      const avoid: string[] = [];
      for (const row of rows) {
        if (row.dir === f.dir) {
          avoid.push(row.name);
        }
      }
      const physChildDirs: string[] = childDirs.get(f.dir) ?? [];
      for (const seg of physChildDirs) {
        avoid.push(seg);
      }
      let displayName: string =
        dedupeWorkspaceName(sanitizeWorkspaceName('恢复_' + f.physName), avoid);
      // 避重后缀可能推过 80 再截回（照 WorkspaceDbTmp.promote 同款防线——原缺二次截回，
      // 越闸名落库后名称闸恒拒，成模型不可达幽灵件）。截回复查：sanitize 保头截尾可把
      // 「80 字既有名 + (2)」截回还原 avoid 原名——落库即 (dir,name) 重复行恒 amb、同名
      // 操作全卡死，复查再避重一次；仍越 80 的双重建构回落幽灵件形态〔管理页可删〕，两害取轻
      if (displayName.length > 80) {
        displayName = sanitizeWorkspaceName(displayName);
        // 截回复查：复查再避重一次（见上）
        displayName = dedupeWorkspaceName(displayName, avoid);
      }
      const fileId: string = util.generateRandomUUID(true);
      // ext 自 displayName 派生（原自 f.physName 派生有坑——sanitize 截断后两处 ext 脱钩，
      // 物理名与行 localPath 不同源 = 死行 + 孤儿，要等下次启动对账才自愈；displayName 派生
      // 与 buildWorkspaceRow 的行派生同源，改名与入库一次对齐）
      const ext: string = extOfWorkspaceName(displayName);
      const dirAbs: string = rootAbs + (f.dir === '' ? '' : '/' + f.dir);
      fs.renameSync(absOld, dirAbs + '/' + workspaceFileName(fileId, ext));
      const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, stat.size,
        WORKSPACE_SOURCE_RECOVERED, '', '', stat.mtime * 1000, 'other', f.dir);
      await insertWorkspaceRow(db, row);
      rows.push(row);
      summary.filesRecovered++;
      hilog.info(DOMAIN, TAG, '工作区对账补录：%{public}s → 「%{public}s」（%{public}s）',
        f.relPath, displayName, f.dir === '' ? '根目录' : f.dir);
    } catch (e) {
      // 单文件失败跳过——下次启动再判（有界自愈）
      hilog.warn(DOMAIN, TAG, '工作区对账补录失败（跳过）：%{public}s %{public}s',
        f.relPath, (e as Error).message);
    }
  }
  // ②目录行登记（对账第三向）：物理目录无目录行 → 登记（source='recovered'，name=物理段名
  // **照录**——外部塞的怪名目录可见可删，模型能否进它取决于段名过不过目录闸；push 回 rows
  // 让下方死行判定覆盖新行——物理目录亡即行删）
  const knownDirPaths: Set<string> = new Set<string>();
  for (const row of rows) {
    if (isWorkspaceDirRow(row)) {
      knownDirPaths.add(joinDirName(row.dir, row.name));
    }
  }
  for (const relDirPath of physDirs) {
    if (knownDirPaths.has(relDirPath)) {
      continue;
    }
    try {
      const parentOf: string = relDirPath.indexOf('/') < 0 ? '' :
        relDirPath.substring(0, relDirPath.lastIndexOf('/'));
      const segOf: string = relDirPath.substring(relDirPath.lastIndexOf('/') + 1);
      const dirRow: WorkspaceFileRow = buildWorkspaceDirRow(util.generateRandomUUID(true),
        segOf, parentOf, WORKSPACE_SOURCE_RECOVERED, '', '', Date.now());
      // v50：对账登记的目录行同落父层底（与两铸造点同判据——排序域）
      dirRow.sortOrder = await nextWorkspaceDirOrder(db, parentOf);
      await insertWorkspaceRow(db, dirRow);
      rows.push(dirRow);
      summary.dirsRegistered++;
      hilog.info(DOMAIN, TAG, '工作区对账登记目录行：%{public}s', relDirPath);
    } catch (e) {
      // 单目录失败跳过——下次启动再判（有界自愈）
      hilog.warn(DOMAIN, TAG, '工作区对账登记目录行失败（跳过）：%{public}s %{public}s',
        relDirPath, (e as Error).message);
    }
  }
  // ③删行（行有文件无）：localPath 磁盘不存在的行清除——「行在文件不在」在下次启动时
  // 清理，行不再长存
  const deadIds: string[] = [];
  for (const row of rows) {
    let alive = true;
    try {
      alive = fs.accessSync(filesDir + '/' + row.localPath);
    } catch {
      alive = false;
    }
    if (!alive) {
      deadIds.push(row.id);
    }
  }
  if (deadIds.length > 0) {
    await deleteWorkspaceRowsByIds(db, deadIds);
    summary.rowsRemoved = deadIds.length;
  }
  hilog.info(DOMAIN, TAG,
    '工作区一致性对账完成：补录 %{public}d 个文件、登记 %{public}d 个文件夹、清除 %{public}d 条失效记录',
    summary.filesRecovered, summary.dirsRegistered, summary.rowsRemoved);
  return summary;
}
