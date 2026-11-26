// 压缩包三工具域：zip_list 条目清单 / zip_extract 解压吸入工作区 / zip_create 文件夹打包
//（desc / schema / 三执行器）。· 常量归口 ToolIds.ets、注册块落 ToolTypes.ets（本文件只产
// 定义件与执行器）；契约自叶子 ToolContracts 引（坑50：零 ToolTypes 引用防环）。
// · 依赖方向照 HttpBinary 引面先例：WorkspaceUtil 纯函数与限额常量直引 + WorkspaceDb 物理
//   帮助直引（ensureWorkspaceDir / removeWorkspaceTree 等）+ ChatDb 委托优先（查/铸目录行/
//   upsert/回滚删行）+ DbWriteQueue 写串行链；容器解析纯核在 common/workspace/ZipArchiveCore
//   （零 import 可 node 直跑，本件不重复实现解析）。
// · zlib 三线纪律（继承 WorkspaceXlsx 头注释两实锤 + @ohos.zlib d.ts）：打包恒
//   compressFile(整目录)——条目名 = 相对目录路径结构保真，禁 compressFiles（条目名抹平成
//   basename，走到必坏）；产物目标恒 .zip 后缀（平台 CheckDestDirTail 静默改道坑）+ 产物
//   到场断言；decompressFile 的 outFile 目录必须预建（d.ts「must exist」三处原文）。
// · zip_extract 落点 = 瞬态解压 + 实测值执法 + 吸入正式区（R3 裁定）：解压到
//   workspace-tmp/<会话id>/extract-<时间戳+序> 瞬态树（tmp 区列举/总量闸对子目录失明——
//   R2-V4 实证，故自有限额组执法而不依赖 tmp 闸），fs walk 实测后按显示名清洗 + 物理名恒
//   UUID 吸入 workspace/<产物目录>/<子段>/<uuid>.<ext> 并落行（先落文件后写行、行写失败
//   回滚自清）。声明值可伪造，实测是第二道闸（压缩炸弹缓解）。
// · 输入只收工作区相对路径（R7）：附件源引导先 workspace_import；定位链照 workspace 族
//   (dir, name) 二元组先例，零/多命中与目录行命中均中文报错。
// · 平台语义差异（★ 2026-10-31 两小修笔 ⑥）：目录创建一律走 ensureDirAllowExists——
//   OHOS 的 recursive mkdir 对已存在目录仍抛 13900015，与 node 相反；打包链两处必踩（单文件
//   目录首件 destDir === stageDir、同目录第二件起），dev 直跑恒绿而真机必炸。
// · 空文件夹预检（★ 同日 #6）：平台解压侧不支持含空目录条目的包（zlib d.ts compressFile
//   原文），zip_extract 在解压前按 ZipArchiveCore.zipEmptyDirEntries 提前拒绝并给准确文案。
// · 回执口径：成功纯文本（编排层 clipToolResultForToolSpilled 统一收口，执行器不自截——
//   仅 list 的百条列出行窗是自带收口）、失败 JSON { error }；大 zip 解压耗时未做
//   TaskPool 化（性能不许愿——真机卡顿再立项，观察哨在 BLOCKED 真机清单）。
import { BusinessError, zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { queryWorkspaceFiles, queryWorkspaceFilesByName, queryWorkspaceTotal,
  ensureWorkspaceDirRowsOp, upsertWorkspaceFile, deleteWorkspaceRowsByIdsOp } from '../store/ChatDb';
import { dirChildSegments, ensureWorkspaceDir, removeWorkspaceFiles, removeWorkspaceTree,
  workspaceFilesDir } from '../store/WorkspaceDb';
import { ensureWorkspaceTmpConversationDir } from '../store/WorkspaceDbTmp';
import { runWriteQueued } from '../store/DbWriteQueue';
import { ZipEntryInfo, ZipGateLimits, ZipMeasuredFile, parseZipCentralDir,
  planZipExtractLayout, zipEmptyDirEntries, zipEntrySafetyReasons } from '../workspace/ZipArchiveCore';
import { WorkspaceFileRow, buildWorkspaceRow, dedupeWorkspaceName, extOfWorkspaceName,
  formatWorkspaceSize, isWorkspaceDirRow, joinDirName, normalizeWorkspaceDirParam,
  relativeWorkspacePath, sanitizeWorkspaceName, workspaceCapacityReason,
  workspaceDirRejectReason, workspaceFileName, workspaceNameRejectReason,
  workspaceParentDir, workspaceUploadDisplayName, WORKSPACE_ROWS_READ_MAX,
  WORKSPACE_SOURCE_ASSISTANT, ZIP_CREATE_OUTPUT_MAX_BYTES, ZIP_ENTRY_MAX_COUNT,
  ZIP_EXPAND_MAX_BYTES, ZIP_INPUT_MAX_BYTES, ZIP_MEMBER_MAX_BYTES } from '../WorkspaceUtil';

// ── desc（请求侧 description，中文三段式——调用时机 / 用法 / 划界）──
export const ZIP_LIST_DESC: string =
  '查看文件工作区里一个压缩包的条目清单。name 是压缩包文件名，取自 workspace_list 的结果，dir 是它所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。会话附件要先让用户确认后用 workspace_import 存入工作区。返回条目总数、文件与文件夹数量、包大小和声明展开合计，并逐条列出名称与大小，加密、同名与可能乱码的条目会标注。条目过多时只列出一部分并注明总数。要把压缩包解开时改用 zip_extract。';

export const ZIP_EXTRACT_DESC: string =
  '把文件工作区里的压缩包解压存入工作区。name 是压缩包文件名，取自 workspace_list 的结果，dir 是它所在的目录，缺省为该助手的默认文件夹，/ 表示根目录。会话附件要先让用户确认后用 workspace_import 存入工作区。产物会存成工作区里以压缩包名命名的新文件夹，条目过多、展开总量过大、单件过大、加密、有同名条目或含不安全路径的压缩包会被拒绝并说明原因。原压缩包不会被改动，用户可在 设置 → 文件工作区 查看与分享产物。';

export const ZIP_CREATE_DESC: string =
  '把文件工作区里的一个文件夹打包成压缩包。source_dir 是要打包的文件夹路径，相对工作区根目录，多级用 / 分隔，例如 项目/资料，取自 workspace_list 返回的子文件夹，文件夹里至少要有一个文件。name 可省略，是产物压缩包的文件名，以 .zip 结尾，缺省用文件夹名。产物保存在源文件夹所在的位置，用户可在 设置 → 文件工作区 查看与分享。要解开压缩包时用 zip_extract。';

// ── schema（JSON Schema 原串；dir 描述句 = 定位版〔缺省落助手默认文件夹、/ 表根——照
//    ToolWorkspace.DIR_PROP 同文，该常量为彼件模块私有不可引，单段复写〕）──
// ★ 2026-10-31 两小修笔 ⑤：source_dir 原缺「相对工作区根目录」定位语义，agent 按族惯例把它
// 理解成别的基准路径，踩空后报「没有名为 X 的文件夹」（真机实测）——补定位句与全路径示例，
// 与 ZIP_DIR_PROP 同句式对齐。
const ZIP_DIR_PROP: string = '"dir":{"type":"string","description":"目录路径，多级用 / 分隔。' +
  '缺省为该助手的默认文件夹，/ 表示根目录。取自 workspace_list 返回的子文件夹。"}';

export const ZIP_LIST_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"要查看的压缩包文件名，取自 workspace_list 的结果。"},' +
  ZIP_DIR_PROP + '},' +
  '"required":["name"]}';

export const ZIP_EXTRACT_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"要解压的压缩包文件名，取自 workspace_list 的结果。"},' +
  ZIP_DIR_PROP + '},' +
  '"required":["name"]}';

export const ZIP_CREATE_SCHEMA: string = '{"type":"object","properties":{' +
  '"source_dir":{"type":"string","description":"要打包的文件夹路径，多级用 / 分隔，相对工作区根目录，例如 项目/资料。取自 workspace_list 返回的子文件夹。"},' +
  '"name":{"type":"string","description":"产物压缩包的文件名，以 .zip 结尾，可省略。"}},' +
  '"required":["source_dir"]}';

// args 解析取串（工具域共用形态）
function argsString(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw : '';
}

// 瞬态树与暂存目录唯一段序号（同毫秒多笔防撞——d.ts outFile 互异明文）
let zipOpSeq: number = 0;

// 定位结果（resolveWorkspaceSource 产物；row 在 ok=true 时恒非空）
interface WorkspaceSourceOutcome {
  ok: boolean;
  errorText: string;
  row: WorkspaceFileRow | null;
}

// 工作区文件定位（零/多命中与目录行命中三态中文报错，照 workspace 族定位链同句）
async function resolveWorkspaceSource(name: string,
  dir: string): Promise<WorkspaceSourceOutcome> {
  const where: string = dir === '' ? '根目录' : '「' + dir + '」目录';
  const matches: WorkspaceFileRow[] = await queryWorkspaceFilesByName(dir, name);
  if (matches.length === 0) {
    return { ok: false, errorText: '工作区' + where + '没有名为「' + name +
      '」的文件。请先用 workspace_list 查看该目录里的文件名。', row: null };
  }
  if (matches.length > 1) {
    return { ok: false, errorText: '工作区' + where + '存在多个名为「' + name +
      '」的文件（数据异常），无法确定操作哪一份。请用户在 设置 → 文件工作区 中删除重复文件。',
      row: null };
  }
  const row: WorkspaceFileRow = matches[0];
  if (isWorkspaceDirRow(row)) {
    return { ok: false, errorText: '「' + name + '」是文件夹，不是文件。要看里面的内容，把 ' +
      name + ' 填入 dir 调用 workspace_list。', row: null };
  }
  return { ok: true, errorText: '', row: row };
}

// 整包读字节（≤ ZIP_INPUT_MAX_BYTES 闸 + 短读守卫——readSync 可短读，读满循环按实读长度
// 收口，照 HttpBinary.readUploadSourceAsBuffer 红线先例；超限抛总表同文句）
function readZipBytes(absPath: string): Uint8Array {
  const stat: fs.Stat = fs.statSync(absPath);
  if (stat.size > ZIP_INPUT_MAX_BYTES) {
    throw new Error('文件超过大小上限。无法处理。');
  }
  const buf: ArrayBuffer = new ArrayBuffer(stat.size);
  const file: fs.File = fs.openSync(absPath, fs.OpenMode.READ_ONLY);
  try {
    let total: number = fs.readSync(file.fd, buf);
    while (total > 0 && total < stat.size) {
      const tmp: ArrayBuffer = new ArrayBuffer(stat.size - total);
      const n: number = fs.readSync(file.fd, tmp);
      if (n <= 0) {
        break; // EOF 早于 stat——按已读长度截断
      }
      new Uint8Array(buf).set(new Uint8Array(tmp, 0, n), total);
      total += n;
    }
    return new Uint8Array(total === stat.size ? buf : buf.slice(0, total));
  } finally {
    fs.closeSync(file);
  }
}

// 条目名「可能乱码」判定（bit11 未设且名含非 ASCII——GBK 中文名包通常 bit11 未设）
function zipEntryMaybeGarbled(entries: ZipEntryInfo[]): boolean {
  for (const entry of entries) {
    if (entry.flagsUtf8Name) {
      continue;
    }
    for (let i: number = 0; i < entry.name.length; i++) {
      if (entry.name.charCodeAt(i) > 0x7F) {
        return true;
      }
    }
  }
  return false;
}

// 壳层策略复检：条目路径段过工作区口径闸（段长 ≤80 / 深度 ≤8 / 空段——zipEntrySafetyReasons
// 的穿越闸更严，本检补工作区结构性口径；'' = 放行）
function zipEntryWorkspaceReason(entries: ZipEntryInfo[]): string {
  for (const entry of entries) {
    if (entry.isDir) {
      const dirPath: string = entry.name.substring(0, entry.name.length - 1);
      if (dirPath !== '' && workspaceDirRejectReason(dirPath) !== '') {
        return '压缩包内条目「' + entry.name + '」无法放入工作区。' +
          workspaceDirRejectReason(dirPath) + '。';
      }
      continue;
    }
    const slash: number = entry.name.lastIndexOf('/');
    const dirPart: string = slash < 0 ? '' : entry.name.substring(0, slash);
    const basePart: string = slash < 0 ? entry.name : entry.name.substring(slash + 1);
    if (dirPart !== '' && workspaceDirRejectReason(dirPart) !== '') {
      return '压缩包内条目「' + entry.name + '」无法放入工作区。' +
        workspaceDirRejectReason(dirPart) + '。';
    }
    if (workspaceNameRejectReason(basePart) !== '') {
      return '压缩包内条目「' + entry.name + '」无法放入工作区。' +
        workspaceNameRejectReason(basePart) + '。';
    }
  }
  return '';
}

// fs walk 实测枚举（照启动对账 walk 形态——文件相对路径 + 实测字节；单件 stat 失败跳过，
// 实测闸以到场件为准）
function walkExtractTree(absDir: string): ZipMeasuredFile[] {
  const files: ZipMeasuredFile[] = [];
  const walk = (dirAbs: string, relDir: string): void => {
    let names: string[] = [];
    try {
      names = fs.listFileSync(dirAbs);
    } catch {
      return; // 目录不存在 = 目标状态
    }
    for (const nm of names) {
      const child: string = dirAbs + '/' + nm;
      try {
        if (fs.statSync(child).isDirectory()) {
          walk(child, relDir === '' ? nm : relDir + '/' + nm);
        } else {
          files.push({ relPath: relDir === '' ? nm : relDir + '/' + nm,
            size: fs.statSync(child).size });
        }
      } catch {
        // 单件失败跳过——实测闸以到场件为准
      }
    }
  };
  walk(absDir, '');
  return files;
}

// 吸入编排结果（链内不抛约定——失败路自带清理后以 errorText 返回）
interface ZipIngestOutcome {
  ok: boolean;
  errorText: string;
  receipt: string;
}

// zip_extract 吸入段回滚（best-effort 逐腿、不吞上游错误）：已落行删行 + 已移入物理文件删
// + 产物目录行与物理树清 + 瞬态树清；残留由启动对账自愈（磁盘为事实源）
async function rollbackZipExtract(insertedIds: string[], movedAbs: string[],
  productName: string, extractDir: string): Promise<void> {
  try {
    if (insertedIds.length > 0) {
      removeWorkspaceFiles(await deleteWorkspaceRowsByIdsOp(insertedIds));
    }
  } catch {
    // 回滚失败留残留：对账自愈兜底，不吞上游错误
  }
  for (const abs of movedAbs) {
    try {
      fs.unlinkSync(abs);
    } catch {
      // 同上
    }
  }
  try {
    const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
    const dirIds: string[] = [];
    for (const r of rows) {
      if (isWorkspaceDirRow(r)) {
        const full: string = joinDirName(r.dir, r.name);
        if (full === productName || full.startsWith(productName + '/')) {
          dirIds.push(r.id);
        }
      }
    }
    if (dirIds.length > 0) {
      await deleteWorkspaceRowsByIdsOp(dirIds);
    }
  } catch {
    // 同上
  }
  removeWorkspaceTree(extractDir);
  const filesDir: string = workspaceFilesDir();
  if (filesDir !== '') {
    removeWorkspaceTree(filesDir + '/' + relativeWorkspacePath('', productName));
  }
}

// ── zip_list：定位 → 读字节 → 解析 → 清单回执（纯读路零 DB 写、零瞬态）──
export class ZipListExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name').trim();
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    try {
      const locate = await resolveWorkspaceSource(name, dir);
      if (!locate.ok || locate.row === null) {
        return JSON.stringify({ error: locate.errorText });
      }
      const filesDir: string = workspaceFilesDir();
      if (filesDir === '') {
        return JSON.stringify({ error: '工作区目录未就绪，无法读取文件' });
      }
      const bytes: Uint8Array = readZipBytes(filesDir + '/' + locate.row.localPath);
      const entries: ZipEntryInfo[] = parseZipCentralDir(bytes);
      let fileCount = 0;
      let dirCount = 0;
      let declaredTotal = 0;
      const nameCounts: Map<string, number> = new Map<string, number>();
      for (const entry of entries) {
        if (entry.isDir) {
          dirCount++;
        } else {
          fileCount++;
        }
        declaredTotal += entry.originalSize;
        nameCounts.set(entry.name, (nameCounts.get(entry.name) ?? 0) + 1);
      }
      const lines: string[] = ['压缩包「' + locate.row.name + '」共 ' + entries.length +
        ' 个条目，其中文件 ' + fileCount + ' 个、文件夹 ' + dirCount + ' 个，包大小 ' +
        formatWorkspaceSize(bytes.length) + '，声明展开合计 ' + formatWorkspaceSize(declaredTotal) + '。'];
      const LIST_CAP: number = 100;
      const shown: number = Math.min(entries.length, LIST_CAP);
      for (let i: number = 0; i < shown; i++) {
        const entry: ZipEntryInfo = entries[i];
        let line: string = '- ' + entry.name;
        if (entry.isDir) {
          line += '（文件夹）';
        } else {
          line += '：' + formatWorkspaceSize(entry.originalSize) + '，压缩后 ' +
            formatWorkspaceSize(entry.compressedSize);
        }
        if (entry.isEncrypted) {
          line += '〔加密〕';
        }
        if ((nameCounts.get(entry.name) ?? 0) > 1) {
          line += '〔同名〕';
        }
        if (!entry.flagsUtf8Name) {
          for (let k: number = 0; k < entry.name.length; k++) {
            if (entry.name.charCodeAt(k) > 0x7F) {
              line += '〔可能乱码〕';
              break;
            }
          }
        }
        lines.push(line);
      }
      if (entries.length > LIST_CAP) {
        lines.push('条目较多，仅列出前 ' + LIST_CAP + ' 条。共 ' + entries.length + ' 条。');
      }
      const dupNames: string[] = [];
      nameCounts.forEach((count: number, nm: string): void => {
        if (count > 1 && dupNames.length < 10) {
          dupNames.push(nm);
        }
      });
      if (dupNames.length > 0) {
        lines.push('同名条目：' + dupNames.join('、') + '。');
      }
      if (zipEntryMaybeGarbled(entries)) {
        lines.push('有部分条目名未标注 UTF-8 编码，显示可能乱码。');
      }
      return lines.join('\n');
    } catch (e) {
      return JSON.stringify({ error: (e as Error).message });
    }
  }
}

// ── zip_extract：定位 → 解析与四闸 → 壳层复检 → 声明值预检 → 链内〔瞬态解压 → 实测值
//    执法 → 吸入正式区 → 清理〕。链体不抛（失败路自带清理以 errorText 返回）──
export class ZipExtractExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const name: string = argsString(parsed, 'name').trim();
    const dir: string = normalizeWorkspaceDirParam(argsString(parsed, 'dir'), ctx.assistantId);
    const reject: string = workspaceNameRejectReason(name);
    if (reject !== '') {
      return JSON.stringify({ error: reject });
    }
    const dirReject: string = workspaceDirRejectReason(dir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    if (ctx.conversationId === '') {
      return JSON.stringify({ error: '本工具只在会话中可用，当前执行上下文没有会话。' });
    }
    try {
      const locate = await resolveWorkspaceSource(name, dir);
      if (!locate.ok || locate.row === null) {
        return JSON.stringify({ error: locate.errorText });
      }
      const filesDir: string = workspaceFilesDir();
      if (filesDir === '') {
        return JSON.stringify({ error: '工作区目录未就绪，无法读取文件' });
      }
      const absZip: string = filesDir + '/' + locate.row.localPath;
      const bytes: Uint8Array = readZipBytes(absZip);
      const entries: ZipEntryInfo[] = parseZipCentralDir(bytes);
      const gateLimits: ZipGateLimits = { maxEntries: ZIP_ENTRY_MAX_COUNT,
        maxTotalBytes: ZIP_EXPAND_MAX_BYTES, maxMemberBytes: ZIP_MEMBER_MAX_BYTES };
      const reasons: string[] = zipEntrySafetyReasons(entries, gateLimits);
      if (reasons.length > 0) {
        return JSON.stringify({ error: reasons.join('\n') });
      }
      const shellReject: string = zipEntryWorkspaceReason(entries);
      if (shellReject !== '') {
        return JSON.stringify({ error: shellReject });
      }
      // 空文件夹预检（★ 2026-10-31 两小修笔 #6）：平台解压侧对「压缩空文件夹」产出的包报错
      //（@ohos.zlib d.ts compressFile 原文），而 Windows 右键压缩含空子目录正产这种包——解压
      // 必败且回执落在平台通用错误/「损坏」话术上（全目录包的实测 0 文件更是直接命中原
      // measuredCount === 0 的假「损坏」句）。提前拒绝并给准确文案；真损坏包（解析层三负例）
      // 文案不动。判据纯核在 ZipArchiveCore.zipEmptyDirEntries（零 import 可直跑断言）。
      const emptyDirs: string[] = zipEmptyDirEntries(entries);
      if (emptyDirs.length > 0) {
        const shown: string[] = [];
        for (const dirName of emptyDirs.slice(0, 3)) {
          shown.push(dirName.charAt(dirName.length - 1) === '/' ?
            dirName.substring(0, dirName.length - 1) : dirName);
        }
        return JSON.stringify({ error: '压缩包内含空文件夹，设备解压组件不支持，已拒绝。' +
          '空文件夹：' + shown.join('、') +
          (emptyDirs.length > shown.length ?
            '，另有 ' + (emptyDirs.length - shown.length) + ' 个' : '') + '。' });
      }
      // 声明值容量预检（早拒省无谓解压；链内实测值是权威闸）
      let declaredFiles = 0;
      let declaredTotal = 0;
      for (const entry of entries) {
        if (!entry.isDir) {
          declaredFiles++;
          declaredTotal += entry.originalSize;
        }
      }
      const totalEarly = await queryWorkspaceTotal();
      const earlyCap: string = workspaceCapacityReason(declaredTotal,
        totalEarly.count + declaredFiles, totalEarly.bytes);
      if (earlyCap !== '') {
        return JSON.stringify({ error: '工作区容量不足。已拒绝解压。' + earlyCap });
      }
      const outcome: ZipIngestOutcome = await runWriteQueued('zipExtractIngest',
        (): Promise<ZipIngestOutcome> => runZipExtractIngest(absZip, filesDir,
          locate.row as WorkspaceFileRow, entries, ctx.conversationId, ctx.assistantId));
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      return outcome.receipt;
    } catch (e) {
      return JSON.stringify({ error: '解压失败：' + toolErrorText(e) });
    }
  }
}

// 吸入链节体（唯一调用方 = ZipExtractExecutor，经 runWriteQueued 入链壳）
async function runZipExtractIngest(absZip: string, filesDir: string, row: WorkspaceFileRow,
  entries: ZipEntryInfo[], conversationId: string,
  assistantId: string): Promise<ZipIngestOutcome> {
  const fail = (text: string): ZipIngestOutcome => ({ ok: false, errorText: text, receipt: '' });
  const insertedIds: string[] = [];
  const movedAbs: string[] = [];
  let extractDir: string = '';
  let productName: string = '';
  // 瞬态树（唯一段防并行冲突——d.ts outFile 互异明文）
  try {
    const tmpBase: string = ensureWorkspaceTmpConversationDir(conversationId);
    zipOpSeq++;
    extractDir = tmpBase + '/extract-' + Date.now() + '-' + zipOpSeq;
    fs.mkdirSync(extractDir, true);
  } catch (e) {
    return fail('临时区目录未就绪，无法解压：' + (e as Error).message);
  }
  // 平台解压（outFile 已预建；inFile 须 .zip 后缀——非 .zip 物理名在此中文报错）
  try {
    await zlib.decompressFile(absZip, extractDir);
  } catch (e) {
    removeWorkspaceTree(extractDir);
    return fail('压缩包解压失败：' + toolErrorText(e));
  }
  // 实测值执法（声明值可伪造，实测是第二道闸）
  const measured: ZipMeasuredFile[] = walkExtractTree(extractDir);
  let measuredTotal = 0;
  let measuredCount = 0;
  let memberOver = false;
  const sizeByRel: Map<string, number> = new Map<string, number>();
  for (const file of measured) {
    measuredTotal += file.size;
    measuredCount++;
    sizeByRel.set(file.relPath, file.size);
    if (file.size > ZIP_MEMBER_MAX_BYTES) {
      memberOver = true;
    }
  }
  if (measuredCount === 0) {
    removeWorkspaceTree(extractDir);
    return fail('压缩包损坏或不是有效的 zip 格式。');
  }
  if (measuredTotal > ZIP_EXPAND_MAX_BYTES || measuredCount > ZIP_ENTRY_MAX_COUNT) {
    removeWorkspaceTree(extractDir);
    return fail('压缩包条目数或展开总量超过上限。已拒绝。');
  }
  if (memberOver) {
    removeWorkspaceTree(extractDir);
    return fail('压缩包内单件超过大小上限。已拒绝解压。');
  }
  const total = await queryWorkspaceTotal();
  const capacityReason: string = workspaceCapacityReason(measuredTotal,
    total.count + measuredCount, total.bytes);
  if (capacityReason !== '') {
    removeWorkspaceTree(extractDir);
    return fail('工作区容量不足。已拒绝解压。' + capacityReason);
  }
  // 吸入映射（纯核）+ 同名二义防线（同段名「文件夹 × 文件」二义态在此拦截，照创建面
  // 三层把守语义）
  const layout = planZipExtractLayout(measured);
  const dirFullPath: Set<string> = new Set<string>(layout.dirSegments);
  for (const plan of layout.filePlans) {
    if (dirFullPath.has(joinDirName(plan.dir, plan.baseName))) {
      removeWorkspaceTree(extractDir);
      return fail('压缩包内既有名为「' + plan.baseName +
        '」的文件夹又有同名文件。已拒绝解压。');
    }
  }
  // 产物目录名（zip 显示名去后缀；根内查重重名加序号；过目录闸）
  const baseName: string = extOfWorkspaceName(row.name) === '' ? row.name :
    row.name.substring(0, row.name.length - extOfWorkspaceName(row.name).length - 1);
  productName = sanitizeWorkspaceName(baseName === '' ? '解压文件' : baseName);
  const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
  const rootNames: string[] = [];
  for (const r of allRows) {
    if (r.dir === '') {
      rootNames.push(r.name);
    }
  }
  for (const seg of dirChildSegments(allRows, '')) {
    rootNames.push(seg);
  }
  productName = dedupeWorkspaceName(productName, rootNames);
  if (productName.length > 80) {
    // 避重后缀推过 80 再截回复查（照 promote 同款防线——截回可还原撞名原名，复查再避重）
    productName = dedupeWorkspaceName(sanitizeWorkspaceName(productName), rootNames);
  }
  const productReject: string = workspaceDirRejectReason(productName);
  if (productReject !== '') {
    removeWorkspaceTree(extractDir);
    return fail(productReject);
  }
  // 吸入：物理目录就绪 + 目录行铸造（产物根与各子目录段，幂等）→ 逐文件 rename + 落行
  try {
    ensureWorkspaceDir(productName);
    await ensureWorkspaceDirRowsOp(productName, WORKSPACE_SOURCE_ASSISTANT,
      conversationId, assistantId);
    for (const segFull of layout.dirSegments) {
      ensureWorkspaceDir(productName + '/' + segFull);
      await ensureWorkspaceDirRowsOp(productName + '/' + segFull,
        WORKSPACE_SOURCE_ASSISTANT, conversationId, assistantId);
    }
  } catch (e) {
    await rollbackZipExtract(insertedIds, movedAbs, productName, extractDir);
    return fail('解压失败：工作区记录写入失败：' + (e as Error).message);
  }
  const takenNames: Map<string, string[]> = new Map<string, string[]>();
  for (const plan of layout.filePlans) {
    const targetDir: string = joinDirName(productName, plan.dir);
    const taken: string[] = takenNames.get(targetDir) ?? [];
    const displayName: string = dedupeWorkspaceName(
      sanitizeWorkspaceName(plan.baseName), taken);
    taken.push(displayName);
    takenNames.set(targetDir, taken);
    const relPath: string = joinDirName(plan.dir, plan.baseName);
    const size: number = sizeByRel.get(relPath) ?? 0;
    const fileId: string = util.generateRandomUUID(true);
    const newRow: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, size,
      WORKSPACE_SOURCE_ASSISTANT, conversationId, assistantId, Date.now(), 'other', targetDir);
    const dstAbs: string = filesDir + '/' + newRow.localPath;
    const srcAbs: string = extractDir + '/' + relPath;
    try {
      fs.renameSync(srcAbs, dstAbs); // 物理名恒 UUID 红线（WorkspaceDb :830 同源）
      movedAbs.push(dstAbs);
      await upsertWorkspaceFile(newRow);
      insertedIds.push(fileId);
    } catch (e) {
      await rollbackZipExtract(insertedIds, movedAbs, productName, extractDir);
      return fail('解压失败：' + (e as Error).message);
    }
  }
  // 成功收尾：清瞬态残树（文件已全部 rename 走，剩空目录）
  removeWorkspaceTree(extractDir);
  const receiptLines: string[] = ['解压完成。共 ' + layout.filePlans.length +
    ' 件，已存入工作区「' + productName + '」。原文档未改动。'];
  receiptLines.push('共 ' + layout.filePlans.length + ' 个文件、' + layout.dirSegments.length +
    ' 个文件夹，合计 ' + formatWorkspaceSize(measuredTotal) +
    '。用户可在 设置 → 文件工作区 查看与分享。');
  if (zipEntryMaybeGarbled(entries)) {
    receiptLines.push('压缩包内文件名可能显示乱码。');
  }
  return { ok: true, errorText: '', receipt: receiptLines.join('\n') };
}

// ── zip_create：定位源 dir 行 → 枚举子树与预检 → 链内〔暂存重铸显示名副本树 → 整目录
//    打包到场断言 → 吸入单文件行 → 清暂存〕──
export class ZipCreateExecutor implements ToolExecutor {
  async execute(argsJson: string, ctx: ToolExecutionContext): Promise<string> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(argsJson) as Record<string, Object>;
    } catch (e) {
      return JSON.stringify({ error: toolArgsParseErrorText(argsJson) });
    }
    const rawDir: string = argsString(parsed, 'source_dir').trim();
    if (rawDir === '') {
      return JSON.stringify({ error: '请提供要打包的文件夹路径，取自 workspace_list 的结果。' });
    }
    const sourceDir: string = normalizeWorkspaceDirParam(rawDir, ctx.assistantId);
    const dirReject: string = workspaceDirRejectReason(sourceDir);
    if (dirReject !== '') {
      return JSON.stringify({ error: dirReject });
    }
    if (ctx.conversationId === '') {
      return JSON.stringify({ error: '本工具只在会话中可用，当前执行上下文没有会话。' });
    }
    // 产物名定稿（.zip 后缀收口在链内名清洗前——入参缺省用文件夹名）
    let rawName: string = argsString(parsed, 'name').trim();
    try {
      const filesDir: string = workspaceFilesDir();
      if (filesDir === '') {
        return JSON.stringify({ error: '工作区目录未就绪，无法读取文件' });
      }
      const rows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
      let dirHit = false;
      const files: WorkspaceFileRow[] = [];
      for (const r of rows) {
        if (isWorkspaceDirRow(r)) {
          if (joinDirName(r.dir, r.name) === sourceDir) {
            dirHit = true;
          }
          continue;
        }
        if (r.dir === sourceDir || r.dir.startsWith(sourceDir + '/')) {
          files.push(r);
        }
      }
      if (!dirHit) {
        // ★ 2026-10-31 两小修笔 ⑤：定位语义引导（真机踩空原文只报名字、不给正确姿势——尾部
        // 补全路径说明；全文替换旧「请先用 workspace_list 确认」，避免同句两提该工具）
        return JSON.stringify({ error: '工作区没有名为「' + sourceDir +
          '」的文件夹。请提供相对根目录的完整路径，可从 workspace_list 结果获取。' });
      }
      if (files.length === 0) {
        return JSON.stringify({ error: '源目录没有文件。已拒绝打包。' });
      }
      let sourceTotal = 0;
      for (const f of files) {
        sourceTotal += f.size;
      }
      if (files.length > ZIP_ENTRY_MAX_COUNT || sourceTotal > ZIP_CREATE_OUTPUT_MAX_BYTES) {
        return JSON.stringify({ error: '压缩包条目数或展开总量超过上限。已拒绝。' });
      }
      if (rawName === '') {
        rawName = sourceDir.substring(sourceDir.lastIndexOf('/') + 1) + '.zip';
      }
      if (extOfWorkspaceName(rawName) !== 'zip') {
        rawName = rawName + '.zip';
      }
      const outcome: ZipIngestOutcome = await runWriteQueued('zipCreateIngest',
        (): Promise<ZipIngestOutcome> => runZipCreateIngest(filesDir, sourceDir, rawName,
          files, ctx.conversationId, ctx.assistantId));
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      return outcome.receipt;
    } catch (e) {
      return JSON.stringify({ error: '打包失败：' + toolErrorText(e) });
    }
  }
}

// 建目录并放行「已存在」（★ 2026-10-31 两小修笔 ⑥，真机实锤）：OHOS 的 fs.mkdirSync(path, true)
// 在目标目录已存在时仍抛 13900015「File exists」，与 node 语义相反——zip_create 打包链两处
// 必踩：单文件目录（该文件 dir === sourceDir → relDisplay '' → destDir === stageDir）与同目录
// 第二件起。dev 断言（node 直跑）恒绿而真机必炸，故此处不能靠「recursive 已存在即静默」的
// node 直觉。照 WorkspaceDb.ensureWorkspaceDir / WorkspaceDbTmp.ensureWorkspaceTmpConversationDir
// 两先例形态：只吞该码，其余错误照抛（禁宽 catch——失败要如实上抛给中文呈报）。
function ensureDirAllowExists(absDir: string): void {
  try {
    fs.mkdirSync(absDir, true);
  } catch (e) {
    const err = e as BusinessError;
    if (err.code !== 13900015) {
      throw e as Error;
    }
  }
}

// 打包链节体（唯一调用方 = ZipCreateExecutor，经 runWriteQueued 入链壳）
async function runZipCreateIngest(filesDir: string, sourceDir: string, rawName: string,
  files: WorkspaceFileRow[], conversationId: string,
  assistantId: string): Promise<ZipIngestOutcome> {
  const fail = (text: string): ZipIngestOutcome => ({ ok: false, errorText: text, receipt: '' });
  const parentDir: string = workspaceParentDir(sourceDir);
  // 暂存目录：按显示名重铸副本树（物理名是 UUID 直接压必产废包——C2-1.1；displayName 恒
  // 单段无 / \ ..，跨目录同名在 zip 目录隔离下不冲突）
  let stageDir: string = '';
  try {
    const tmpBase: string = ensureWorkspaceTmpConversationDir(conversationId);
    zipOpSeq++;
    stageDir = tmpBase + '/zipbuild-' + Date.now() + '-' + zipOpSeq;
    ensureDirAllowExists(stageDir);
    for (const f of files) {
      const relDisplay: string = f.dir === sourceDir ? '' :
        f.dir.substring(sourceDir.length + 1);
      const destDir: string = stageDir + (relDisplay === '' ? '' : '/' + relDisplay);
      ensureDirAllowExists(destDir);
      const src: fs.File = fs.openSync(filesDir + '/' + f.localPath, fs.OpenMode.READ_ONLY);
      try {
        const dest: fs.File = fs.openSync(destDir + '/' + f.name,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.copyFileSync(src.fd, dest.fd);
        } finally {
          fs.closeSync(dest);
        }
      } finally {
        fs.closeSync(src);
      }
    }
  } catch (e) {
    if (stageDir !== '') {
      removeWorkspaceTree(stageDir);
    }
    return fail('打包失败：文件复制失败：' + (e as Error).message);
  }
  // 落库名收口（链内现读避重——上传链同款单源收口；目标位置名 ∪ 子文件夹段名）
  const allRows: WorkspaceFileRow[] = await queryWorkspaceFiles(WORKSPACE_ROWS_READ_MAX);
  const existing: string[] = [];
  for (const r of allRows) {
    if (r.dir === parentDir) {
      existing.push(r.name);
    }
  }
  for (const seg of dirChildSegments(allRows, parentDir)) {
    existing.push(seg);
  }
  const displayName: string = workspaceUploadDisplayName(rawName, existing);
  const fileId: string = util.generateRandomUUID(true);
  const absOut: string = filesDir + '/' +
    relativeWorkspacePath(parentDir, workspaceFileName(fileId, 'zip'));
  try {
    ensureWorkspaceDir(parentDir);
    await ensureWorkspaceDirRowsOp(parentDir, WORKSPACE_SOURCE_ASSISTANT,
      conversationId, assistantId);
    // 整目录打包 + 到场断言（两平台坑防线，照 WorkspaceXlsx 同款）
    const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
    await zlib.compressFile(stageDir, absOut, options);
    if (!fs.accessSync(absOut, fs.AccessModeType.EXIST)) {
      throw new Error('产物文件未出现在预期位置，已放弃保存。');
    }
    // 实测产物容量闸（压缩后真值；先落文件后写行，行写失败自清）
    const trueSize: number = fs.statSync(absOut).size;
    const total = await queryWorkspaceTotal();
    const capacityReason: string = workspaceCapacityReason(trueSize, total.count, total.bytes);
    if (capacityReason !== '') {
      try {
        fs.unlinkSync(absOut);
      } catch {
        // 残留由清空工作区兜底，不吞上游错误
      }
      removeWorkspaceTree(stageDir);
      return fail('工作区容量不足。已拒绝打包。' + capacityReason);
    }
    const row: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, trueSize,
      WORKSPACE_SOURCE_ASSISTANT, conversationId, assistantId, Date.now(), 'other', parentDir);
    try {
      await upsertWorkspaceFile(row);
    } catch (e) {
      try {
        fs.unlinkSync(absOut);
      } catch {
        // 同上
      }
      removeWorkspaceTree(stageDir);
      return fail('打包失败：工作区记录写入失败：' + (e as Error).message);
    }
  } catch (e) {
    removeWorkspaceTree(stageDir);
    try {
      fs.unlinkSync(absOut);
    } catch {
      // 目标不存在 = 目标状态
    }
    return fail('打包失败：' + (e as Error).message);
  }
  removeWorkspaceTree(stageDir);
  let sourceTotal = 0;
  for (const f of files) {
    sourceTotal += f.size;
  }
  return { ok: true, errorText: '', receipt: '打包完成。产物已存入工作区。\n产物「' +
    displayName + '」位于' + (parentDir === '' ? '根目录' : '「' + parentDir + '」目录') +
    '，共打包 ' + files.length + ' 件、源文件合计 ' + formatWorkspaceSize(sourceTotal) +
    '。用户可在 设置 → 文件工作区 查看与分享。' };
}
