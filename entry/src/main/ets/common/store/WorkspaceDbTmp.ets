// 临时产物区存储域：filesDir/workspace-tmp/<会话id>/ 会话粒度易失区的 IO 与转存编排。
// 独立成件而非落 WorkspaceDb.ets：彼件剔头已越宪法 1200 硬线须先拆域，临时区是新功能域
// 独立成缝天然合规；依赖方向 ChatDb → 本件 → WorkspaceDb/WorkspaceUtil 单向，本件**禁
// import ChatDb**（防环——conversations 反查经句柄传参直查，MemoryDb 直查 assistants 同款）。
// · 三不红线（负向钉守）：临时区永不进 workspace_files 表、不进启动对账（reconcile
//   Workspace 只扫 workspace 目录）、不进备份导出——本件是唯一写口，落库仅发生在
//   promoteWorkspaceTmpFile 转正时；反方向桥 stageWorkspaceFileToTmp（拷贝语义、零落库、
//   源零改动）与转正的「移动 + 落库」语义对立，两桥不得互相抄语义。
// · 生命周期：随会话删除级联清（deleteConversations 链内收集 + commit 后两段式——照
//   message_attachments 先例）+ 管理页临时段手动清理兜底；无启动清扫（拍板否决——保
//  「聊一半重启接力」）。删除实现：本 SDK ets API 无 fs.rmSync（d.ts 实核改判）——复用
//   WorkspaceDb.removeWorkspaceTree 后序递归删，目标不存在 = 达成态。
// · 写事务入全局写链：promote 落库行段入 runWriteQueued；先落文件 → 后写行，行写失败
//   自清刚拷文件（write 铁律同款）。
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { WorkspaceFileRow, buildWorkspaceRow, dedupeWorkspaceName,
  defaultWorkspaceDirForAssistant, extOfWorkspaceName,
  sanitizeWorkspaceName, workspaceFileName, workspaceNameRejectReason,
  workspaceUploadDisplayName, workspaceUploadGateReason, workspaceCapacityReason,
  WORKSPACE_NAME_MAX_CHARS, WORKSPACE_ROWS_READ_MAX,
  WORKSPACE_SOURCE_ASSISTANT } from '../WorkspaceUtil';
import { WorkspaceTmpFileBrief, WorkspaceTmpGroupBrief, WorkspaceTmpScan,
  workspaceTmpConversationDir,
  workspaceTmpDir, workspaceTmpStageGateReason, workspaceTmpWriteGateReason,
  WORKSPACE_TMP_LIST_MAX } from '../WorkspaceTmpUtil';
// 统计聚合：五类分类与载荷组装在纯函数件，本件只做 IO 收集
import { buildTmpDataStats, WorkspaceDataStats, WorkspaceStatFile }
  from '../WorkspaceStatsUtil';
import { runWriteQueued } from './DbWriteQueue';
import { dirChildSegments, ensureWorkspaceDir, ensureWorkspaceDirRows,
  insertWorkspaceRow,
  queryWorkspaceFiles, queryWorkspaceTotal, removeWorkspaceTree,
  workspaceFilesDir } from './WorkspaceDb';

const DOMAIN: number = 0xDA4B;
const TAG: string = 'WorkspaceDbTmp';

// 模块级 ctx 捕获（照 initWorkspaceStore 先例——EntryAbility onCreate 调一次，紧邻其后）
let tmpCtx: common.UIAbilityContext | null = null;

// ctx 捕获（先于任何临时区文件操作；目录懒建——首次写入方建）
export function initWorkspaceTmpStore(ctx: common.UIAbilityContext): void {
  tmpCtx = ctx;
}

// 捕获 ctx 的临时区根读出口（未捕获回 ''——消费方按「目录未就绪」处理）
export function workspaceTmpRootDir(): string {
  return tmpCtx !== null ? workspaceTmpDir(tmpCtx.filesDir) : '';
}

// 读单件全文（exec_output_read 工具读盘口）：文件不在场 statSync 上抛由调用方转中文；
// UTF-8 直解（本口恒文本件；stage 桥拷入的二进制件模型侧走沙箱 fs.readBytes 读字节）
export function readWorkspaceTmpFileText(conversationId: string, fileName: string): string {
  if (tmpCtx === null) {
    throw new Error('临时区目录未就绪，无法读取文件');
  }
  const abs: string = workspaceTmpConversationDir(tmpCtx.filesDir, conversationId) +
    '/' + fileName;
  const st: fs.Stat = fs.statSync(abs);
  const file: fs.File = fs.openSync(abs, fs.OpenMode.READ_ONLY);
  try {
    const buf: ArrayBuffer = new ArrayBuffer(st.size);
    const got: number = fs.readSync(file.fd, buf);
    return util.TextDecoder.create('utf-8')
      .decodeWithStream(new Uint8Array(buf, 0, got));
  } finally {
    fs.closeSync(file);
  }
}

// 会话临时子目录就绪（mkdirSync 容 EEXIST 静默——目录已在场 = 目标状态；其余错误上抛由调用方转中文）
export function ensureWorkspaceTmpConversationDir(conversationId: string): string {
  if (tmpCtx === null) {
    throw new Error('临时区目录未就绪，无法创建会话目录');
  }
  const dir: string = workspaceTmpConversationDir(tmpCtx.filesDir, conversationId);
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

// 写单件文本（exec_code 的 data 落件口）：名称闸 + 清洗 → 两闸预检（纯函数单源）→ UTF-8
// 直写，返回清洗后落盘名；越限/闸拒抛中文 Error。落件名由调用方以唯一段生成，同名覆盖
// 分支不可达不设防）
export function writeWorkspaceTmpTextFile(conversationId: string, fileName: string,
  text: string): string {
  if (tmpCtx === null) {
    throw new Error('临时区目录未就绪，无法写入文件');
  }
  const reject: string = workspaceNameRejectReason(fileName);
  if (reject !== '') {
    throw new Error(reject);
  }
  const cleaned: string = sanitizeWorkspaceName(fileName);
  // 字节量（空串短路——d.ts 明示 encodeInto 空串返回 undefined）
  const byteLen: number = text === '' ? 0 :
    util.TextEncoder.create('utf-8').encodeInto(text).length;
  let existing: number = 0;
  for (const brief of listWorkspaceTmpFileBriefs(conversationId)) {
    existing += brief.size;
  }
  const gateReason: string = workspaceTmpWriteGateReason(byteLen, existing);
  if (gateReason !== '') {
    throw new Error(gateReason);
  }
  const abs: string = workspaceTmpConversationDir(tmpCtx.filesDir, conversationId) +
    '/' + cleaned;
  const file: fs.File = fs.openSync(abs,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
  return cleaned;
}

// 单会话临时件全集（列举/组清单/计数三口共享扫盘单源，防多口径漂移）：非目录件、mtime
// 降序、不截断；目录不存在 = 空集
function listWorkspaceTmpFileBriefs(conversationId: string): WorkspaceTmpFileBrief[] {
  if (tmpCtx === null) {
    return [];
  }
  const dir: string = workspaceTmpConversationDir(tmpCtx.filesDir, conversationId);
  let names: string[] = [];
  try {
    names = fs.listFileSync(dir);
  } catch {
    return [];
  }
  const files: WorkspaceTmpFileBrief[] = [];
  for (const name of names) {
    try {
      const stat: fs.Stat = fs.statSync(dir + '/' + name);
      if (stat.isDirectory()) {
        continue; // 临时区内平铺无子目录，异常目录不计件
      }
      files.push({ name: name, size: stat.size, mtime: stat.mtime * 1000 });
    } catch {
      // 单件 stat 失败跳过（并发删除等）
    }
  }
  files.sort((a: WorkspaceTmpFileBrief, b: WorkspaceTmpFileBrief): number => b.mtime - a.mtime);
  return files;
}

// 单会话临时件列举（管理页下探行）：mtime 降序，越 WORKSPACE_TMP_LIST_MAX 截断置
// truncated；目录不存在 = 空集
export function listWorkspaceTmpFiles(conversationId: string): WorkspaceTmpScan {
  const files: WorkspaceTmpFileBrief[] = listWorkspaceTmpFileBriefs(conversationId);
  if (files.length > WORKSPACE_TMP_LIST_MAX) {
    return { files: files.slice(0, WORKSPACE_TMP_LIST_MAX), truncated: true };
  }
  return { files: files, truncated: false };
}

// 临时区会话组清单（管理页组列表）：扫根列**非空**会话子目录（空目录不显示——级联删整
// 目录删，漏网孤儿必有件），mtime 降序。fileCount/bytes 取目录全集（组卡「清理」删整目录
// ——载荷与级联删除面同界；截断只属下探列举面）
export function listWorkspaceTmpGroups(): WorkspaceTmpGroupBrief[] {
  if (tmpCtx === null) {
    return [];
  }
  let names: string[] = [];
  try {
    names = fs.listFileSync(workspaceTmpDir(tmpCtx.filesDir));
  } catch {
    return [];
  }
  const groups: WorkspaceTmpGroupBrief[] = [];
  for (const id of names) {
    const files: WorkspaceTmpFileBrief[] = listWorkspaceTmpFileBriefs(id);
    if (files.length === 0) {
      continue;
    }
    let bytes = 0;
    let lastAt = 0;
    for (const f of files) {
      bytes += f.size;
      if (f.mtime > lastAt) {
        lastAt = f.mtime;
      }
    }
    groups.push({ conversationId: id, fileCount: files.length, bytes: bytes, lastAt: lastAt });
  }
  groups.sort((a: WorkspaceTmpGroupBrief, b: WorkspaceTmpGroupBrief): number => b.lastAt - a.lastAt);
  return groups;
}

// 单会话临时件计数（删除拦截弹窗文案用；目录不存在 = 0）——不受列举上限截断（级联删除面
// = 目录全集，计数须同界，>500 件时数字不失实）
export function countWorkspaceTmpFiles(conversationId: string): number {
  return listWorkspaceTmpFileBriefs(conversationId).length;
}

// 临时区总占用（管理页统计行）——按目录全集求和（与级联删除面同界）
export function workspaceTmpTotalBytes(): number {
  let total = 0;
  for (const group of listWorkspaceTmpGroups()) {
    total += group.bytes;
  }
  return total;
}

// 临时区数据总览（管理页面板载荷）：一次扫全——复用 listWorkspaceTmpFileBriefs 扫盘单源；
// 空目录沿用组清单口径不计。根不存在或 ctx 未捕获 = 全零载荷（不谎报）；分类与聚合在
// WorkspaceStatsUtil 纯函数
export function scanWorkspaceTmpOverview(): WorkspaceDataStats {
  if (tmpCtx === null) {
    return buildTmpDataStats([], 0);
  }
  let names: string[] = [];
  try {
    names = fs.listFileSync(workspaceTmpDir(tmpCtx.filesDir));
  } catch {
    return buildTmpDataStats([], 0);
  }
  const files: WorkspaceStatFile[] = [];
  let conversations: number = 0;
  for (const id of names) {
    const briefs: WorkspaceTmpFileBrief[] = listWorkspaceTmpFileBriefs(id);
    if (briefs.length === 0) {
      continue;
    }
    conversations++;
    for (const brief of briefs) {
      files.push({ name: brief.name, size: brief.size });
    }
  }
  return buildTmpDataStats(files, conversations);
}

// 级联收集（deleteConversations 链内调用——彼件越 1200 硬线，收集落本件）：返回临时目录在场的会话 id 子集（空目录也收——级联删目标是目录整体消失）
export function collectTmpForConversations(ids: string[]): string[] {
  if (tmpCtx === null || ids.length === 0) {
    return [];
  }
  const hit: string[] = [];
  for (const id of ids) {
    try {
      if (fs.accessSync(workspaceTmpConversationDir(tmpCtx.filesDir, id))) {
        hit.push(id);
      }
    } catch {
      // 不存在 = 无级联对象
    }
  }
  return hit;
}

// 级联删除（commit 后 best-effort——失败 hilog 留痕不回滚，照 removeAttachmentFiles 口径）
export function deleteWorkspaceTmpConversationsQuiet(ids: string[]): void {
  if (tmpCtx === null || ids.length === 0) {
    return;
  }
  for (const id of ids) {
    try {
      removeWorkspaceTree(workspaceTmpConversationDir(tmpCtx.filesDir, id));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '会话临时区级联删除失败（留待手动清理，会话 %{public}s）：%{public}s',
        id, (e as Error).message);
    }
  }
}

// 删单会话临时区（管理页组卡「清理」键；目标不存在 = 达成态不报错）
export function deleteWorkspaceTmpConversation(conversationId: string): void {
  if (tmpCtx === null) {
    return;
  }
  removeWorkspaceTree(workspaceTmpConversationDir(tmpCtx.filesDir, conversationId));
}

// 删单件临时文件（管理页文件行「删除」键；name 须单段显示名）
export function deleteWorkspaceTmpFile(conversationId: string, fileName: string): void {
  if (tmpCtx === null) {
    return;
  }
  const absPath: string =
    workspaceTmpConversationDir(tmpCtx.filesDir, conversationId) + '/' + fileName;
  try {
    fs.unlinkSync(absPath);
  } catch {
    // 文件不存在 = 目标状态
  }
}

// 清空整个临时区（管理页「清理临时区」菜单项；根不存在 = 达成态）
export function clearWorkspaceTmpAll(): void {
  if (tmpCtx === null) {
    return;
  }
  removeWorkspaceTree(workspaceTmpDir(tmpCtx.filesDir));
}

// 转存结果（displayName = 含序号的最终落库名，toast 用；dir = 实际落点目录）
export interface PromoteOutcome {
  ok: boolean;
  displayName: string;
  dir: string;
  errorText: string;
}

// 会话临时件反查归属助手（conversations 直查防环；行不存在或 assistantId 空 → ''）
async function tmpConversationAssistantId(db: relationalStore.RdbStore,
  conversationId: string): Promise<string> {
  const result: relationalStore.ResultSet = await db.querySql(
    'SELECT assistantId FROM conversations WHERE id = ?', [conversationId]);
  try {
    if (result.goToNextRow()) {
      return result.getString(result.getColumnIndex('assistantId'));
    }
    return '';
  } finally {
    result.close();
  }
}

// 转存「保存」键（临时件 → 正式工作区）：读临时件 → 归属反查（dir = 会话助手默认目录，
// 查不到回退 '' 落根）→ 正式区三闸 → 同名追加序号（用户显式动作静默覆盖他件不可接受——
// 覆盖语义留给模型 write）→ fd 流拷贝 → 落 workspace_files 行（source='assistant'）→ 删
// 临时件。落库段入写串行链，行写失败自清刚拷文件（write 铁律）
export function promoteWorkspaceTmpFile(db: relationalStore.RdbStore, conversationId: string,
  fileName: string): Promise<PromoteOutcome> {
  return runWriteQueued('promoteWorkspaceTmpFile', async (): Promise<PromoteOutcome> => {
    const failed = (text: string): PromoteOutcome =>
      ({ ok: false, displayName: '', dir: '', errorText: text });
    const nameReject: string = workspaceNameRejectReason(fileName);
    if (nameReject !== '') {
      return failed(nameReject);
    }
    if (tmpCtx === null) {
      return failed('临时区目录未就绪，无法保存');
    }
    const srcAbs: string =
      workspaceTmpConversationDir(tmpCtx.filesDir, conversationId) + '/' + fileName;
    let size = 0;
    try {
      size = fs.statSync(srcAbs).size;
    } catch (e) {
      return failed('临时文件已不在本机：' + (e as Error).message);
    }
    // 归属与落点（会话已删 / 助手反查失败 → 回退根目录，不谎报）
    const assistantId: string = await tmpConversationAssistantId(db, conversationId);
    const dir: string = defaultWorkspaceDirForAssistant(assistantId);
    // 正式区三闸：单件（上传档——转存是既有件的搬运非模型新写）+ 件数/总量
    const total = await queryWorkspaceTotal(db);
    const sizeGate: string = workspaceUploadGateReason(fileName, size);
    if (sizeGate !== '') {
      return failed(sizeGate);
    }
    const capacityGate: string = workspaceCapacityReason(size, total.count, total.bytes);
    if (capacityGate !== '') {
      return failed(capacityGate);
    }
    // 落库名收口（上传链同款：清洗 → 目录内避重〔文件名 ∪ 子文件夹段名，永不制造同名二义
    // 态〕；后缀可能推过 80 再截回）
    const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(db, WORKSPACE_ROWS_READ_MAX);
    const existing: string[] = [];
    for (const row of allRows) {
      if (row.dir === dir) {
        existing.push(row.name);
      }
    }
    for (const seg of dirChildSegments(allRows, dir)) {
      existing.push(seg);
    }
    let displayName: string = sanitizeWorkspaceName(fileName);
    displayName = dedupeWorkspaceName(displayName, existing);
    if (displayName.length > 80) {
      displayName = sanitizeWorkspaceName(displayName);
      // 截回复查（★ 防 sanitize 保头截尾把「80 字既有名 + (2)」截回还原 existing 原名——落库
      // 即重复 (dir,name) 行恒 amb、同名操作全卡死，复查再避重；仍越 80 回落幽灵件形态，两害取轻）
      displayName = dedupeWorkspaceName(displayName, existing);
    }
    // 目录就绪 + 目录行铸造（隐式建目录入账——助手文件夹因此天然出现在管理页文件夹段）
    let dirAbs: string = '';
    try {
      dirAbs = ensureWorkspaceDir(dir);
      await ensureWorkspaceDirRows(db, dir, WORKSPACE_SOURCE_ASSISTANT, conversationId,
        assistantId);
    } catch (e) {
      return failed('文件保存失败：' + (e as Error).message);
    }
    // fd 流拷贝（先落文件 → 后写行；kind 三类外落 other 档——下载/上传路同口径）
    const fileId: string = util.generateRandomUUID(true);
    const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, size,
      WORKSPACE_SOURCE_ASSISTANT, conversationId, assistantId, Date.now(), 'other', dir);
    const absPath: string = dirAbs + '/' +
      workspaceFileName(fileId, extOfWorkspaceName(displayName));
    const src: fs.File = fs.openSync(srcAbs, fs.OpenMode.READ_ONLY);
    try {
      const dest: fs.File = fs.openSync(absPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
    } catch (e) {
      // 拷贝失败自清半截目标（不清会被启动对账补录为恢复件——write 铁律两腿齐备；目标名
      // 含新铸 UUID 无误删他件可能）
      try {
        fs.unlinkSync(absPath);
      } catch {
        // 自清失败留残留：可手动清理兜底，不吞原始错误
      }
      return failed('文件保存失败：' + (e as Error).message);
    } finally {
      fs.closeSync(src);
    }
    try {
      await insertWorkspaceRow(db, row);
    } catch (e) {
      try {
        fs.unlinkSync(absPath);
      } catch {
        // 自清失败留残留：「清空工作区」清整个目录兜底，不吞原始错误
      }
      return failed('工作区记录写入失败：' + (e as Error).message);
    }
    // 转正完成删临时件（best-effort——失败留临时段可见可清，不回滚已成功的转存）
    try {
      fs.unlinkSync(srcAbs);
    } catch {
      // 残留由临时段「清理」兜底
    }
    return { ok: true, displayName: displayName, dir: dir, errorText: '' };
  });
}

// 放入结果（ok=true：name = 临时区落定名〔撞名时含序号〕，size = 实拷字节）
export interface StageOutcome {
  ok: boolean;
  errorText: string;
  name: string;
  size: number;
}

// 入向桥「放入」（工作区件 → 本会话临时区，拷贝语义）：名称闸 → 源件 stat 实测（闸判据用
// 物理字节不用行 size——对账窗口下两者可漂移）→ 两闸预检（总量 = 本会话临时目录合计，与
// 沙箱 fs 闸同口径，全机合计不用）→ 终名派生（不撞名透传；撞名 dedupe 加序号，越 80 收口）
// → fd 三步拷贝（**源件零改动零删除**——拷贝不是移动，失败自清只针对目标半截件）→ 零 DB
// 写（三不红线）。全程入写链（同轮并发放入的终名判定不穿窗）
export function stageWorkspaceFileToTmp(conversationId: string, srcRelPath: string,
  displayName: string): Promise<StageOutcome> {
  return runWriteQueued('stageWorkspaceFileToTmp', async (): Promise<StageOutcome> => {
    const failed = (text: string): StageOutcome =>
      ({ ok: false, errorText: text, name: '', size: 0 });
    const nameReject: string = workspaceNameRejectReason(displayName);
    if (nameReject !== '') {
      return failed(nameReject);
    }
    if (tmpCtx === null) {
      return failed('临时区目录未就绪，无法放入文件');
    }
    if (workspaceFilesDir() === '') {
      return failed('工作区目录未就绪，无法读取文件');
    }
    const srcAbs: string = workspaceFilesDir() + '/' + srcRelPath;
    let size = 0;
    try {
      size = fs.statSync(srcAbs).size;
    } catch (e) {
      return failed('工作区文件不在本机：' + (e as Error).message);
    }
    // 现有件与总量（私有扫盘单源复用——不截断全集，终名避重与总量求值同界）
    const existingBriefs: WorkspaceTmpFileBrief[] = listWorkspaceTmpFileBriefs(conversationId);
    let existingTotalBytes = 0;
    const existingNames: string[] = [];
    for (const brief of existingBriefs) {
      existingTotalBytes += brief.size;
      existingNames.push(brief.name);
    }
    const gate: string = workspaceTmpStageGateReason(displayName, size, existingTotalBytes);
    if (gate !== '') {
      return failed(gate);
    }
    let destDirAbs: string = '';
    try {
      destDirAbs = ensureWorkspaceTmpConversationDir(conversationId);
    } catch (e) {
      return failed('临时区目录未就绪，无法放入文件：' + (e as Error).message);
    }
    let finalName: string = displayName;
    if (existingNames.indexOf(finalName) >= 0) {
      finalName = dedupeWorkspaceName(finalName, existingNames);
      if (finalName.length > WORKSPACE_NAME_MAX_CHARS) {
        finalName = workspaceUploadDisplayName(displayName, existingNames);
      }
    }
    const destAbs: string = destDirAbs + '/' + finalName;
    const src: fs.File = fs.openSync(srcAbs, fs.OpenMode.READ_ONLY);
    try {
      const dest: fs.File = fs.openSync(destAbs,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, dest.fd);
      } finally {
        fs.closeSync(dest);
      }
    } catch (e) {
      // 拷贝失败自清半截目标（best-effort——删不掉留残留由管理页临时段与「清空临时区」
      // 兜底，不吞原始错误；**不碰源文件**）
      try {
        fs.unlinkSync(destAbs);
      } catch {
        // 自清失败留残留，不吞原始错误
      }
      return failed('放入临时区失败：' + (e as Error).message);
    } finally {
      fs.closeSync(src);
    }
    return { ok: true, errorText: '', name: finalName, size: size };
  });
}
