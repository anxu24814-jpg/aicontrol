// Office 补丁工具域：office_patch 单工具多操作——docx / xlsx / pptx 定点改写后另存新文件
//（desc / schema / 执行器）。· 常量归口 ToolIds.ets、注册块落 ToolTypes.ets（本文件只产
// 定义件与执行器）；契约自叶子 ToolContracts 引（坑50：零 ToolTypes 引用防环）。
// · 改写纯核在 common/workspace/OoxmlPatchCore.ets（零 import 可 node 直跑，本件不重复
// 实现改写）；容器解析预检复用 common/workspace/ZipArchiveCore.ets（加密位 / 坏包判）。
// · 依赖方向照 ToolZip 引面先例（HttpBinary 同源）：WorkspaceUtil 纯函数与限额常量直引 +
// ChatDb 委托（定位 / upsert / 目录行铸造）+ WorkspaceDb 物理帮助直引 + DbWriteQueue 写
// 串行链。zlib 纪律继承（compressFile 整目录 / 产物压缩出口恒 .zip 后缀 + 到场断言 /
// decompressFile 前目录预建 + 解包源瞬态 .zip 复制〔d.ts inFile 须 .zip 后缀，源原件零改动〕
// + 产物打包后改名 <uuid>.<显示名扩展> 对齐落库行——行 localPath 与物理名一致对账不变量）。
// · 流程 = 瞬态解包 → 部件定位（docx = word/document.xml；pptx = 枚举 ppt/slides/slideN.xml
// 逐件改写命中合计；xlsx = sheet 名经 xl/workbook.xml → r:id → xl/_rels/workbook.xml.rels →
// target 字符串级解析，缺省第一张）→ 部件文本内存改写（fail-fast：任一 op 失败整批不落盘，
// 全或无）→ 写回 → 暂存重铸打包 → 产物吸收入正式区单文件行（**恒写新文件禁覆盖原文件**，
// 物理名恒 UUID + 显示名 dedupe + 容量闸 + kind = classifyWorkspaceName）→ 清暂存。
// · ops 为 JSON 数组原串（string 型全 provider 兼容——判据同 ToolWorkspace「rows 为 JSON
// 二维数组原串」注释先例）；输入只收工作区相对路径（R7：附件源引导先 workspace_import）。
// · 回执口径：成功纯文本逐 op 命中统计（跨 run 不命中 / 公式不重算如实报告）、失败 JSON
// { error }（编排层 clipToolResultForToolSpilled 统一收口，执行器不自截）。
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ToolExecutor, toolArgsParseErrorText, toolErrorText } from './ToolContracts';
import { ToolExecutionContext } from '../chat/MessageContracts';
import { queryWorkspaceFiles, queryWorkspaceFilesByName, queryWorkspaceTotal,
  ensureWorkspaceDirRowsOp, upsertWorkspaceFile } from '../store/ChatDb';
import { dirChildSegments, ensureWorkspaceDir, removeWorkspaceTree,
  workspaceFilesDir } from '../store/WorkspaceDb';
import { ensureWorkspaceTmpConversationDir } from '../store/WorkspaceDbTmp';
import { runWriteQueued } from '../store/DbWriteQueue';
import { ZipEntryInfo, parseZipCentralDir } from '../workspace/ZipArchiveCore';
import { PatchResult, docxAppendParagraphPart, docxReplaceTextPart, pptxReplaceTextPart,
  xlsxAppendRowPart, xlsxSetCellPart } from '../workspace/OoxmlPatchCore';
import { WorkspaceFileRow, buildWorkspaceRow, classifyWorkspaceName,
  extOfWorkspaceName, formatWorkspaceSize, isWorkspaceDirRow,
  normalizeWorkspaceDirParam, relativeWorkspacePath,
  workspaceCapacityReason, workspaceDirRejectReason, workspaceFileName,
  workspaceNameRejectReason, workspaceUploadDisplayName,
  WORKSPACE_ROWS_READ_MAX, WORKSPACE_SOURCE_ASSISTANT, WORKSPACE_XLSX_CELL_MAX_CHARS,
  OFFICE_PATCH_INPUT_MAX_BYTES } from '../WorkspaceUtil';

// ── desc（请求侧 description，中文三段式——调用时机 / 用法 / 划界）──
export const OFFICE_PATCH_DESC: string =
  '编辑文件工作区里的 Office 文档并生成新文件。支持 Word 文档 docx、Excel 表格 xlsx 和 PowerPoint 演示文稿 pptx。name 是文件名，取自 workspace_list 的结果，dir 是它所在的目录，缺省为该助手的默认文件夹。会话附件要先让用户确认后用 workspace_import 存入工作区。ops 是操作列表的 JSON 数组原串，一次可做多项修改，例如 [{\\"op\\":\\"replaceText\\",\\"find\\":\\"旧词\\",\\"replace\\":\\"新词\\"},{\\"op\\":\\"setCell\\",\\"cell\\":\\"B2\\",\\"value\\":\\"新值\\"}]。可用操作：replaceText 替换文字，给 find 与 replace，Word 与 PPT 可用；appendParagraph 在 Word 文档末尾追加一段，给 text；setCell 写入 Excel 单元格，给 cell（A1 形式地址）与 value，可用 sheet 指定工作表名，缺省第一张；appendRow 在 Excel 末尾追加一行，给 values 文字数组。替换只在完整文字段内进行，被排版拆开的文字无法命中，回执会逐项报告命中情况。单元格值以等号开头按公式写入，打开时由表格软件重算。产物是新文件，原文件不会被改动，用户可在 设置 → 文件工作区 查看与分享。';

// ── schema（JSON Schema 原串；dir 描述句 = 定位版，照 ToolZip 同文单段复写）──
export const OFFICE_PATCH_SCHEMA: string = '{"type":"object","properties":{' +
  '"name":{"type":"string","description":"要编辑的 Office 文档文件名，取自 workspace_list 的结果。"},' +
  '"dir":{"type":"string","description":"目录路径，多级用 / 分隔。缺省为该助手的默认文件夹，/ 表示根目录。取自 workspace_list 返回的子文件夹。"},' +
  '"ops":{"type":"string","description":"操作列表的 JSON 数组原串。每项形如 {\\"op\\":\\"setCell\\",\\"sheet\\":\\"Sheet1\\",\\"cell\\":\\"B2\\",\\"value\\":\\"新值\\"}，op 可取 replaceText、appendParagraph、setCell、appendRow。"},' +
  '"output_name":{"type":"string","description":"产物文件名，可省略，缺省在原名后加 _已编辑 并保留原扩展名。"}},' +
  '"required":["name","ops"]}';

// 操作数上限（本件常量；防单笔 ops 原串过长）
const WORKSPACE_OFFICE_OPS_MAX: number = 50;
// 追加行列数上限（Excel 最大列 IV = 256——OOXML 常量非产品闸，与 WorkspaceXlsx.XLSX_MAX_COLS
// 同源规格自持）
const OFFICE_ROW_MAX_COLS: number = 256;

// args 解析取串（工具域共用形态）
function argsString(parsed: Record<string, Object>, key: string): string {
  const raw: Object | undefined = parsed[key];
  return typeof raw === 'string' ? raw : '';
}

// 瞬态暂存目录唯一段序号（同毫秒多笔防撞——d.ts outFile 互异明文）
let officeOpSeq: number = 0;

// 整包读字节（≤ OFFICE_PATCH_INPUT_MAX_BYTES 闸 + 短读守卫——readSync 可短读，读满循环按
// 实读长度收口，照 ToolZip.readZipBytes 同形；超限抛总表同文句）
function readOfficeBytes(absPath: string): Uint8Array {
  const stat: fs.Stat = fs.statSync(absPath);
  if (stat.size > OFFICE_PATCH_INPUT_MAX_BYTES) {
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

// 定位结果（resolveWorkspaceSource 产物；row 在 ok=true 时恒非空——与 ToolZip 同形复用）
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

// 已解析的单项操作（全字段平铺——op 决定消费哪些字段；值域已规整为 string）
interface OfficeOp {
  op: string;          // 'replaceText' | 'appendParagraph' | 'setCell' | 'appendRow'
  find: string;
  replace: string;
  text: string;
  sheet: string;       // '' = 缺省第一张
  cell: string;
  value: string;
  values: string[];
}

// 值规整（ops JSON 值 → 文字；number/boolean 经 String，null 与缺省 = 空串省略节点）
function officeValueText(raw: Object | null | undefined): string {
  if (raw === null || raw === undefined) {
    return '';
  }
  if (typeof raw === 'string') {
    return raw;
  }
  return String(raw);
}

// ops 原串解析与逐项校验（fail-fast 前置——非法项在解包前早拒；docKind 先验 op 兼容性）
function parseOfficeOps(opsRaw: string, docKind: string): OfficeOp[] {
  const arr: Object | null = JSON.parse(opsRaw) as Object | null;
  if (!Array.isArray(arr)) {
    throw new Error('ops 必须是操作对象的 JSON 数组原串。');
  }
  if (arr.length === 0 || arr.length > WORKSPACE_OFFICE_OPS_MAX) {
    throw new Error('操作数量须在 1 到 ' + WORKSPACE_OFFICE_OPS_MAX + ' 项之间，收到 ' +
      arr.length + ' 项。');
  }
  const out: OfficeOp[] = [];
  for (let k: number = 0; k < arr.length; k++) {
    const one: Object = arr[k];
    if (typeof one !== 'object' || one === null || Array.isArray(one)) {
      throw new Error('第 ' + (k + 1) + ' 项操作不是对象。');
    }
    const rec: Record<string, Object> = one as Record<string, Object>;
    const op: string = argsString(rec, 'op');
    const base: OfficeOp = { op: op, find: '', replace: '', text: '', sheet: '',
      cell: '', value: '', values: [] };
    const at: string = '第 ' + (k + 1) + ' 项操作';
    if (op === 'replaceText') {
      if (docKind === 'xlsx') {
        throw new Error(at + ' replaceText 只适用于 Word 文档与 PPT 演示文稿。');
      }
      base.find = argsString(rec, 'find');
      base.replace = argsString(rec, 'replace');
      if (base.find === '') {
        throw new Error(at + '缺少要查找的文字 find。');
      }
    } else if (op === 'appendParagraph') {
      if (docKind !== 'docx') {
        throw new Error(at + ' appendParagraph 只适用于 Word 文档。');
      }
      base.text = argsString(rec, 'text');
      if (base.text === '') {
        throw new Error(at + '缺少要追加的段落文字 text。');
      }
    } else if (op === 'setCell') {
      if (docKind !== 'xlsx') {
        throw new Error(at + ' setCell 只适用于 Excel 表格。');
      }
      base.sheet = argsString(rec, 'sheet');
      base.cell = argsString(rec, 'cell');
      base.value = officeValueText(rec['value']);
      if (base.cell === '') {
        throw new Error(at + '缺少单元格地址 cell（A1 形式）。');
      }
      if (base.value.length > WORKSPACE_XLSX_CELL_MAX_CHARS) {
        throw new Error(at + '的文字超过单元格上限 ' + WORKSPACE_XLSX_CELL_MAX_CHARS +
          ' 字。请减少内容后重试。');
      }
    } else if (op === 'appendRow') {
      if (docKind !== 'xlsx') {
        throw new Error(at + ' appendRow 只适用于 Excel 表格。');
      }
      base.sheet = argsString(rec, 'sheet');
      const rawValues: Object | null | undefined = rec['values'];
      if (!Array.isArray(rawValues)) {
        throw new Error(at + '缺少行内容数组 values。');
      }
      const vals: Object[] = rawValues as Object[];
      if (vals.length === 0 || vals.length > OFFICE_ROW_MAX_COLS) {
        throw new Error(at + '的列数须在 1 到 ' + OFFICE_ROW_MAX_COLS + ' 列之间。');
      }
      for (let c: number = 0; c < vals.length; c++) {
        const cellText: string = officeValueText(vals[c]);
        if (cellText.length > WORKSPACE_XLSX_CELL_MAX_CHARS) {
          throw new Error(at + '第 ' + (c + 1) + ' 列的文字超过单元格上限 ' +
            WORKSPACE_XLSX_CELL_MAX_CHARS + ' 字。请减少内容后重试。');
        }
        base.values.push(cellText);
      }
    } else {
      throw new Error(at + '的 op「' + (op === '' ? '（空）' : op) +
        '」无法识别。可用操作为 replaceText、appendParagraph、setCell、appendRow。');
    }
    out.push(base);
  }
  return out;
}

// xlsx 工作表名 → 部件相对路径（字符串级解析：workbook.xml 名与 r:id → workbook.xml.rels
// 的 target；sheet='' = 第一张）。表名比对双轨（原样 + 转义域）——表名里的 & 等在 XML 里
// 以实体形态存储。
function resolveXlsxSheetRelPath(stageDir: string, sheet: string): string {
  const workbook: string = fs.readTextSync(stageDir + '/xl/workbook.xml');
  const re: RegExp = /<sheet\s[^>]*>/g;
  let firstRid: string = '';
  let hitRid: string = '';
  let m: RegExpExecArray | null = re.exec(workbook);
  while (m !== null) {
    const el: string = m[0];
    const nameMatch: RegExpExecArray | null = /name="([^"]*)"/.exec(el);
    const ridMatch: RegExpExecArray | null = /r:id="([^"]*)"/.exec(el);
    const name: string = nameMatch !== null ? nameMatch[1] : '';
    const rid: string = ridMatch !== null ? ridMatch[1] : '';
    if (firstRid === '') {
      firstRid = rid;
    }
    if (sheet !== '' && name !== '' && rid !== '' &&
      (name === sheet || name ===
        // 转义域比对（本件无 escapeXmlText 导入面——单实体 &amp; 兜底即可覆盖表名常见态）
        sheet.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'))) {
      hitRid = rid;
    }
    m = re.exec(workbook);
  }
  if (firstRid === '') {
    throw new Error('工作簿里没有工作表。');
  }
  const rid: string = sheet === '' ? firstRid : hitRid;
  if (rid === '') {
    throw new Error('工作簿里没有名为「' + sheet + '」的工作表。');
  }
  const rels: string = fs.readTextSync(stageDir + '/xl/_rels/workbook.xml.rels');
  const relRe: RegExp = /<Relationship\s[^>]*>/g;
  let rm: RegExpExecArray | null = relRe.exec(rels);
  while (rm !== null) {
    const el: string = rm[0];
    if (el.indexOf('Id="' + rid + '"') >= 0) {
      if (el.indexOf('TargetMode="External"') >= 0) {
        throw new Error('工作表「' + sheet + '」是外部链接，无法编辑。');
      }
      const tMatch: RegExpExecArray | null = /Target="([^"]*)"/.exec(el);
      if (tMatch === null) {
        break;
      }
      let target: string = tMatch[1];
      if (target.startsWith('/')) {
        target = target.substring(1);
      }
      if (!target.startsWith('xl/')) {
        target = 'xl/' + target;
      }
      return target;
    }
    rm = relRe.exec(rels);
  }
  throw new Error('工作簿结构不完整，找不到工作表「' +
    (sheet === '' ? '（第一张）' : sheet) + '」对应的文件。');
}

// pptx 幻灯片部件枚举（ppt/slides/slideN.xml 全量——替换逐件应用命中合计）
function listPptxSlideRelPaths(stageDir: string): string[] {
  let names: string[] = [];
  try {
    names = fs.listFileSync(stageDir + '/ppt/slides');
  } catch {
    return [];
  }
  const out: string[] = [];
  for (const nm of names) {
    if (/^slide[0-9]+\.xml$/.test(nm)) {
      out.push('ppt/slides/' + nm);
    }
  }
  out.sort();
  return out;
}

// 吸入编排结果（链内不抛约定——失败路自带清理后以 errorText 返回）
interface OfficeOutcome {
  ok: boolean;
  errorText: string;
  receipt: string;
}

// ── office_patch：定位 → 限额与容器预检 → 链内〔暂存解包 → 部件定位 → 内存改写
//    fail-fast → 写回 → 重打包到场断言 → 吸入单文件行 → 清暂存〕。恒写新文件，源零改动 ──
export class OfficePatchExecutor implements ToolExecutor {
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
    const opsRaw: string = argsString(parsed, 'ops');
    if (opsRaw === '') {
      return JSON.stringify({ error: '请提供 ops 操作列表的 JSON 数组原串。' });
    }
    try {
      const ext: string = extOfWorkspaceName(name);
      if (ext !== 'docx' && ext !== 'xlsx' && ext !== 'pptx') {
        return JSON.stringify({ error: 'office_patch 只支持 docx、xlsx、pptx 三种格式，「' +
          name + '」不是其中之一。' });
      }
      const docKind: string = ext;
      const ops: OfficeOp[] = parseOfficeOps(opsRaw, docKind);
      const locate = await resolveWorkspaceSource(name, dir);
      if (!locate.ok || locate.row === null) {
        return JSON.stringify({ error: locate.errorText });
      }
      if (extOfWorkspaceName(locate.row.name) !== ext) {
        return JSON.stringify({ error: '文件「' + locate.row.name + '」的扩展名不是 .' + ext +
          '，无法按该格式编辑。' });
      }
      const filesDir: string = workspaceFilesDir();
      if (filesDir === '') {
        return JSON.stringify({ error: '工作区目录未就绪，无法读取文件' });
      }
      const absSrc: string = filesDir + '/' + locate.row.localPath;
      // 容器预检（20MB 读闸内整读；加密位拒；非 zip / 坏包中文报——Office 文档即 zip 容器）
      const entries: ZipEntryInfo[] = parseZipCentralDir(readOfficeBytes(absSrc));
      let encrypted = false;
      for (const entry of entries) {
        if (entry.isEncrypted) {
          encrypted = true;
          break;
        }
      }
      if (encrypted) {
        return JSON.stringify({ error: '压缩包已加密。暂不支持解压加密压缩包。' });
      }
      const outputName: string = argsString(parsed, 'output_name').trim();
      const outcome: OfficeOutcome = await runWriteQueued('officePatchIngest',
        (): Promise<OfficeOutcome> => runOfficePatchIngest(absSrc, filesDir,
          locate.row as WorkspaceFileRow, docKind, ops, outputName,
          ctx.conversationId, ctx.assistantId));
      if (!outcome.ok) {
        return JSON.stringify({ error: outcome.errorText });
      }
      return outcome.receipt;
    } catch (e) {
      return JSON.stringify({ error: '编辑失败：' + toolErrorText(e) });
    }
  }
}

// 编辑链节体（唯一调用方 = OfficePatchExecutor，经 runWriteQueued 入链壳）
async function runOfficePatchIngest(absSrc: string, filesDir: string, row: WorkspaceFileRow,
  docKind: string, ops: OfficeOp[], outputName: string, conversationId: string,
  assistantId: string): Promise<OfficeOutcome> {
  const fail = (text: string): OfficeOutcome => ({ ok: false, errorText: text, receipt: '' });
  // 暂存目录（唯一段防并行冲突）
  let stageDir: string = '';
  try {
    const tmpBase: string = ensureWorkspaceTmpConversationDir(conversationId);
    officeOpSeq++;
    stageDir = tmpBase + '/officebuild-' + Date.now() + '-' + officeOpSeq;
    fs.mkdirSync(stageDir, true);
  } catch (e) {
    return fail('临时区目录未就绪，无法编辑：' + (e as Error).message);
  }
  // 平台解包（outFile 已预建）。★ zlib d.ts 明文「inFile 文件后缀需要以 .zip 结尾」，而工作区
  // Office 源物理名恒 <uuid>.docx 等（buildWorkspaceRow 按显示名扩展铸造）——直接解包必败
  // （修复笔两千零二十 P0）：先复制为瞬态 .zip 副本再解包，源原件零改动；副本 = stageDir
  // 同名 .zip 兄弟件（落 tmpBase 不入 stageDir 重打包面），解包后即删，失败残留由 tmp 区
  // 生命周期兜底
  const copyZip: string = stageDir + '.zip';
  try {
    fs.copyFileSync(absSrc, copyZip);
  } catch (e) {
    removeWorkspaceTree(stageDir);
    return fail('文档解包失败：' + toolErrorText(e));
  }
  try {
    await zlib.decompressFile(copyZip, stageDir);
  } catch (e) {
    removeWorkspaceTree(stageDir);
    return fail('文档解包失败：' + toolErrorText(e));
  } finally {
    try {
      fs.unlinkSync(copyZip);
    } catch {
      // 副本不在重打包面，删除失败无害——tmp 区生命周期兜底
    }
  }
  // 部件在场预检（早拒省改写）
  if (docKind === 'docx' && !fs.accessSync(stageDir + '/word/document.xml',
    fs.AccessModeType.EXIST)) {
    removeWorkspaceTree(stageDir);
    return fail('文档结构不完整，找不到正文部件，无法编辑。');
  }
  const slides: string[] = docKind === 'pptx' ? listPptxSlideRelPaths(stageDir) : [];
  if (docKind === 'pptx' && slides.length === 0) {
    removeWorkspaceTree(stageDir);
    return fail('演示文稿里没有幻灯片，无法编辑。');
  }
  // 部件文本缓存（多 op 复用同一部件的已改写态；写回 = 缓存里出现过的部件全量落盘）
  const partTexts: Map<string, string> = new Map<string, string>();
  const loadPart = (rel: string): string => {
    const cached: string | undefined = partTexts.get(rel);
    if (cached !== undefined) {
      return cached;
    }
    const text: string = fs.readTextSync(stageDir + '/' + rel);
    partTexts.set(rel, text);
    return text;
  };
  // 逐 op 内存应用（fail-fast：任一失败整批不落盘，全或无）
  const opLines: string[] = [];
  for (let k: number = 0; k < ops.length; k++) {
    const op: OfficeOp = ops[k];
    const at: string = '第 ' + (k + 1) + ' 项 ' + op.op + '：';
    try {
      if (op.op === 'replaceText') {
        let hits = 0;
        if (docKind === 'pptx') {
          for (const slideRel of slides) {
            const r: PatchResult = pptxReplaceTextPart(loadPart(slideRel), op.find, op.replace);
            partTexts.set(slideRel, r.patched);
            hits += r.hits;
          }
        } else {
          const r: PatchResult = docxReplaceTextPart(loadPart('word/document.xml'),
            op.find, op.replace);
          partTexts.set('word/document.xml', r.patched);
          hits = r.hits;
        }
        opLines.push(at + '替换 ' + hits + ' 处，未命中 ' + (hits > 0 ? 0 : 1) + ' 处。');
      } else if (op.op === 'appendParagraph') {
        const r: PatchResult = docxAppendParagraphPart(loadPart('word/document.xml'),
          op.text);
        partTexts.set('word/document.xml', r.patched);
        opLines.push(at + '已追加 1 段。');
      } else if (op.op === 'setCell') {
        const rel: string = resolveXlsxSheetRelPath(stageDir, op.sheet);
        const r: PatchResult = xlsxSetCellPart(loadPart(rel), op.cell, op.value);
        partTexts.set(rel, r.patched);
        opLines.push(at + '已写入 ' + op.cell + '。' + (r.note !== '' ? r.note : ''));
      } else {
        const rel: string = resolveXlsxSheetRelPath(stageDir, op.sheet);
        const r: PatchResult = xlsxAppendRowPart(loadPart(rel), op.values);
        partTexts.set(rel, r.patched);
        opLines.push(at + '已追加 1 行，写入 ' + r.hits + ' 格。');
      }
    } catch (e) {
      removeWorkspaceTree(stageDir);
      return fail('第 ' + (k + 1) + ' 项操作失败。' + (e as Error).message +
        '未生成文件，原文档未改动。');
    }
  }
  // 全部成功 → 写回部件 → 暂存重铸整目录打包（.zip 后缀 + 到场断言两坑防线）
  let absOut: string = '';
  try {
    partTexts.forEach((text: string, rel: string): void => {
      const part: fs.File = fs.openSync(stageDir + '/' + rel,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(part.fd, text);
      } finally {
        fs.closeSync(part);
      }
    });
    // 产物名收口（output_name 无扩展或异扩展 = 补源扩展；sanitize + dedupe 走上传收口先例）
    const ext: string = extOfWorkspaceName(row.name);
    const base: string = ext === '' ? row.name :
      row.name.substring(0, row.name.length - ext.length - 1);
    let rawName: string = outputName !== '' ? outputName : base + '_已编辑.' + ext;
    if (extOfWorkspaceName(rawName) !== ext) {
      rawName = rawName + '.' + ext;
    }
    const parentDir: string = row.dir;
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
    absOut = filesDir + '/' +
      relativeWorkspacePath(parentDir, workspaceFileName(fileId, 'zip'));
    ensureWorkspaceDir(parentDir);
    await ensureWorkspaceDirRowsOp(parentDir, WORKSPACE_SOURCE_ASSISTANT,
      conversationId, assistantId);
    const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
    await zlib.compressFile(stageDir, absOut, options);
    if (!fs.accessSync(absOut, fs.AccessModeType.EXIST)) {
      throw new Error('产物文件未出现在预期位置，已放弃保存。');
    }
    // 产物物理名对齐落库行（修复笔两千零二十 P0）：行 localPath 由 buildWorkspaceRow 按
    // 显示名扩展派生（<uuid>.<显示名扩展>），而 compressFile 出口恒 .zip 后缀——打包到场后
    // 把物理文件改名 <uuid>.<显示名扩展> 再落行，保「行 localPath 与物理名一致」对账不变量
    // （启动对账删行 / 补录两腿都消费它；zip_create 显示名恒 .zip 结尾天然一致不受影响）。
    // absOut 随改名改指——后续容量闸与失败清理腿统一指向物理件现位
    const outExt: string = extOfWorkspaceName(displayName);
    const absFinal: string = filesDir + '/' +
      relativeWorkspacePath(parentDir, workspaceFileName(fileId, outExt));
    fs.renameSync(absOut, absFinal);
    absOut = absFinal;
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
      return fail('工作区容量不足。已拒绝编辑。' + capacityReason);
    }
    const newRow: WorkspaceFileRow = buildWorkspaceRow(fileId, displayName, trueSize,
      WORKSPACE_SOURCE_ASSISTANT, conversationId, assistantId, Date.now(),
      classifyWorkspaceName(displayName), parentDir);
    try {
      await upsertWorkspaceFile(newRow);
    } catch (e) {
      try {
        fs.unlinkSync(absOut);
      } catch {
        // 目标不存在 = 目标状态
      }
      removeWorkspaceTree(stageDir);
      return fail('编辑失败：工作区记录写入失败：' + (e as Error).message);
    }
    removeWorkspaceTree(stageDir);
    const receiptLines: string[] = ['编辑完成。产物「' + displayName + '」已存入工作区，共 ' +
      ops.length + ' 项操作。'];
    for (const line of opLines) {
      receiptLines.push(line);
    }
    receiptLines.push('产物位于' + (parentDir === '' ? '根目录' : '「' + parentDir + '」目录') +
      '，大小 ' + formatWorkspaceSize(trueSize) + '。原文档未改动。');
    return { ok: true, errorText: '', receipt: receiptLines.join('\n') };
  } catch (e) {
    removeWorkspaceTree(stageDir);
    if (absOut !== '') {
      try {
        fs.unlinkSync(absOut);
      } catch {
        // 目标不存在 = 目标状态
      }
    }
    return fail('编辑失败：' + (e as Error).message);
  }
}
