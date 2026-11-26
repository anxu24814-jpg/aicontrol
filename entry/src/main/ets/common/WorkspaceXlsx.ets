// 工作区 xlsx 写出核：纯构建域——rows JSON 二维数组校验与单元格规整、最小 OOXML 五部件
// 构造、zlib 打包、临时件产出到 cacheDir、失败自清。闸与落库编排不在此件（落库编排 =
// WorkspaceDbXlsx.ets〔硬线拆分〕，执行器编排 = ToolWorkspace）。
// · 依赖纪律（坑 50 方向）：只引 kit（zlib/fs/util）与 WorkspaceUtil 常量——零 DB、零工具
//   域、零桥页；上限数值单源 WorkspaceUtil（本件零 10000/32767 字面量）。
// · ★ 手写 XML 而不用 @ohos.xml XmlSerializer：本机 d.ts 实核 XmlSerializer 累计长度上限
//   100000（@throws 10200062），行数上限 10000 行的 sheet1.xml 必超（每行标签开销即数十
//   字）——改手写构造，转义自持标准五实体 + 非法控制字符剔除（XML 1.0 拒收 <0x20）。
// · ★ zip 打包两坑警示（两轮真机报障复检后的定稿口径，两个事实都要守）：
//   ① **目标路径必须以 `.zip` 结尾**——平台实现 FilePath::CheckDestDirTail 对不以 .zip
//   结尾的目标自动追加 `.zip`，产物会静默改道到 `<outFile>.zip`、调用方按原路径读全
//   ENOENT（dest 写 .xlsx 时真机实锤）。本件临时件名以 .zip 结尾规避，压缩后另有产物到
//   场断言兜底（平台姿势再变时报错指向该断言）。
//   ② 打包用 `compressFile(暂存目录)` 整目录形态，弃 `compressFiles(文件路径列表)`——
//   后者条目名取各文件 basename（源码 GetZipsAllRelativeFiles 单文件分支），xl/workbook.xml
//   会被抹平成 workbook.xml、_rels/.rels 抹成 .rels，OOXML 结构整体丢失（走到必坏）；整目
//   录形态条目 = 相对目录路径、`[Content_Types].xml` 在 zip 根（官方单测实证）。全仓导出域
//   同为 .zip 目标写法。平台源码证据 = OpenHarmony bundlemanager_bundle_framework
//   interfaces/kits/js/zip/{src/zip.cpp, src/file_path.cpp}。
// · 本件不可 node 直跑（依赖 @kit API）——断言只做形态钉，行为验证全在真机。
import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { WORKSPACE_XLSX_CELL_MAX_CHARS, WORKSPACE_XLSX_MAX_ROWS } from './WorkspaceUtil';

// 列数上限（Excel 最大列 IV = 256；与行数不同源——256 是 OOXML 常量非产品闸，住本件）
const XLSX_MAX_COLS: number = 256;

// XML 文本转义：标准五实体 + 非法控制字符剔除（\t \n \r 是 XML 1.0 合法控制字符保留）
function escapeXmlText(text: string): string {
  let out: string = '';
  for (const ch of text) {
    const code: number = ch.charCodeAt(0);
    if (code < 0x20 && ch !== '\t' && ch !== '\n' && ch !== '\r') {
      continue;
    }
    if (ch === '&') {
      out += '&amp;';
    } else if (ch === '<') {
      out += '&lt;';
    } else if (ch === '>') {
      out += '&gt;';
    } else if (ch === '"') {
      out += '&quot;';
    } else if (ch === '\'') {
      out += '&apos;';
    } else {
      out += ch;
    }
  }
  return out;
}

// 列序号 → 列字母（1 → A、26 → Z、27 → AA、256 → IV）
function colLetter(colIndex1: number): string {
  let n: number = colIndex1;
  let s: string = '';
  while (n > 0) {
    const rem: number = (n - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

// 工作表名清洗（Excel 硬限：禁 : \ / ? * [ ] 替换 _、截 31 字符不劈代理对、空兜 Sheet1。
// 首尾撇号非法（中段合法）——模型带引号传名（如 '清单'）落库后 Excel/WPS 打开会触发修复
// 提示，SheetJS 反读不校验该规则拦不住；去撇两遍（截 31 前后各一次——截断点恰落撇号上时
// 31 硬限优先收口））
function sanitizeSheetName(name: string): string {
  let cleaned: string = '';
  for (const ch of name) {
    cleaned += ':\\/?*[]'.indexOf(ch) >= 0 ? '_' : ch;
  }
  cleaned = cleaned.trim();
  cleaned = cleaned.replace(/^'+/g, '').replace(/'+$/g, '');
  if (cleaned.length > 31) {
    let cut: number = 31;
    const prev: number = cleaned.charCodeAt(cut - 1);
    if (prev >= 0xD800 && prev <= 0xDBFF) {
      cut -= 1;
    }
    cleaned = cleaned.substring(0, cut);
    cleaned = cleaned.replace(/^'+/g, '').replace(/'+$/g, '');
  }
  return cleaned === '' ? 'Sheet1' : cleaned;
}

// JSON 值的中文名（校验报错用——模型可据此自纠）
function jsonTypeNameOf(value: Object | null | undefined): string {
  if (value === null) {
    return 'null';
  }
  if (Array.isArray(value)) {
    return '数组';
  }
  return typeof value === 'object' ? '对象' : typeof value;
}

// 单元格序列化：number → <v> 数值元；boolean → t="b" 的 1/0；其余（string 原样 / null 与
// 对象数组 String() 化）→ t="inlineStr" 文本格（免 sharedStrings 部件，SheetJS 反读兼容）；
// 空串省略节点（Excel 合法空格）；超上限文字静默截断（Excel 单格硬限 32767）
function cellXml(colIndex1: number, rowIndex1: number, raw: Object | null): string {
  const ref: string = colLetter(colIndex1) + rowIndex1;
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return '<c r="' + ref + '"><v>' + raw + '</v></c>';
  }
  if (typeof raw === 'boolean') {
    return '<c r="' + ref + '" t="b"><v>' + (raw ? 1 : 0) + '</v></c>';
  }
  let text: string;
  if (typeof raw === 'string') {
    text = raw;
  } else if (raw === null || raw === undefined) {
    text = 'null';
  } else {
    text = String(raw);
  }
  if (text === '') {
    return '';
  }
  if (text.length > WORKSPACE_XLSX_CELL_MAX_CHARS) {
    // 截点不劈代理对（sanitizeSheetName 同族先例）：孤立代理逃过 escapeXmlText 剔除、
    // 入 XML 触发 Excel/WPS 修复提示
    let cut: number = WORKSPACE_XLSX_CELL_MAX_CHARS;
    const prev: number = text.charCodeAt(cut - 1);
    if (prev >= 0xD800 && prev <= 0xDBFF) {
      cut -= 1;
    }
    text = text.substring(0, cut);
  }
  return '<c r="' + ref + '" t="inlineStr"><is><t xml:space="preserve">' +
    escapeXmlText(text) + '</t></is></c>';
}

// 五部件 XML 串构造（xlsx 最小集；转义都经 escapeXmlText）
function buildContentTypesXml(): string {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
    '</Types>';
}

function buildRootRelsXml(): string {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
    '</Relationships>';
}

function buildWorkbookXml(sheetName: string): string {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
    '<sheets><sheet name="' + escapeXmlText(sheetName) + '" sheetId="1" r:id="rId1"/></sheets>' +
    '</workbook>';
}

function buildWorkbookRelsXml(): string {
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
    '</Relationships>';
}

function buildSheetXml(grid: Object[]): string {
  const parts: string[] = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'];
  for (let r: number = 0; r < grid.length; r++) {
    const rowRaw: Object = grid[r];
    if (!Array.isArray(rowRaw)) {
      throw new Error('表格数据第 ' + (r + 1) + ' 行不是数组，收到 ' + jsonTypeNameOf(rowRaw) +
        '。每一行都必须是数组。');
    }
    const cells: Object[] = rowRaw as Object[];
    if (cells.length > XLSX_MAX_COLS) {
      throw new Error('表格数据第 ' + (r + 1) + ' 行有 ' + cells.length + ' 列，超过上限 ' +
        XLSX_MAX_COLS + ' 列。请减少列数后重试。');
    }
    let rowXml: string = '<row r="' + (r + 1) + '">';
    for (let c: number = 0; c < cells.length; c++) {
      rowXml += cellXml(c + 1, r + 1, cells[c]);
    }
    parts.push(rowXml + '</row>');
  }
  parts.push('</sheetData></worksheet>');
  return parts.join('');
}

// ── 暂存目录 IO（结构自造固定五文件三层目录——清理路径写死同构）──
function writeTextFile(absPath: string, content: string): void {
  const file: fs.File = fs.openSync(absPath,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file);
  }
}

function removeFileQuiet(absPath: string): void {
  try {
    fs.unlinkSync(absPath);
  } catch {
    // 不存在 = 目标态
  }
}

function cleanupStageDir(stageDir: string): void {
  const files: string[] = ['/[Content_Types].xml', '/_rels/.rels', '/xl/workbook.xml',
    '/xl/_rels/workbook.xml.rels', '/xl/worksheets/sheet1.xml'];
  for (const f of files) {
    removeFileQuiet(stageDir + f);
  }
  const dirs: string[] = ['/xl/worksheets', '/xl/_rels', '/xl', '/_rels'];
  for (const d of dirs) {
    try {
      fs.rmdirSync(stageDir + d);
    } catch {
      // 尽力清理——残留由 cacheDir 系统清理兜底
    }
  }
  try {
    fs.rmdirSync(stageDir);
  } catch {
    // 同上
  }
}

// 主入口：rows JSON 二维数组原串 → 真临时件绝对路径（cacheDir 下；调用方消费后删——
// executor 成败两路都删，成对释放）。失败自清暂存目录与半截产物并抛中文错（P0-1）
export async function buildXlsxToTemp(rowsJson: string, sheetName: string,
  cacheDir: string): Promise<string> {
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(rowsJson) as Object;
  } catch (e) {
    throw new Error('表格数据不是合法的 JSON。请给 JSON 二维数组原串，例如 [[\"品名\",\"数量\"],[\"苹果\",3]]。');
  }
  if (!Array.isArray(parsed)) {
    throw new Error('表格数据必须是 JSON 二维数组，外层收到的是 ' + jsonTypeNameOf(parsed) + '。');
  }
  const grid: Object[] = parsed as Object[];
  if (grid.length === 0) {
    throw new Error('表格数据至少要有一行，第一行是表头。');
  }
  if (grid.length > WORKSPACE_XLSX_MAX_ROWS) {
    throw new Error('表格行数 ' + grid.length + ' 超过上限 ' + WORKSPACE_XLSX_MAX_ROWS +
      ' 行。请减少行数后重试。');
  }
  // 行/列逐项校验与 XML 构造（cellXml 同遍完成；行结构错在此抛中文错）
  const sheetXml: string = buildSheetXml(grid);
  const buildId: string = util.generateRandomUUID(true);
  const stageDir: string = cacheDir + '/xlsx_build_' + buildId;
  // 产物名以 .zip 结尾（规避平台自动补尾改道，见头注释①）；文件名非 .xlsx 无碍——
  // 落库物理名与扩展名取自工具入参 name
  const outFile: string = cacheDir + '/xlsx_build_' + buildId + '.zip';
  try {
    fs.mkdirSync(stageDir + '/_rels', true);
    fs.mkdirSync(stageDir + '/xl/_rels', true);
    fs.mkdirSync(stageDir + '/xl/worksheets', true);
    writeTextFile(stageDir + '/[Content_Types].xml', buildContentTypesXml());
    writeTextFile(stageDir + '/_rels/.rels', buildRootRelsXml());
    writeTextFile(stageDir + '/xl/workbook.xml', buildWorkbookXml(sanitizeSheetName(sheetName)));
    writeTextFile(stageDir + '/xl/_rels/workbook.xml.rels', buildWorkbookRelsXml());
    writeTextFile(stageDir + '/xl/worksheets/sheet1.xml', sheetXml);
    // 整目录打包（条目名 = 相对目录路径、结构保真——见头注释①②）
    const options: zlib.Options = { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION };
    await zlib.compressFile(stageDir, outFile, options);
    // 产物到场断言（平台对 dest 有静默改道史——把「原路径必有产物」钉成显式契约，平台姿势
    // 再变时报错指向本句，而非下游神秘 ENOENT）
    if (!fs.accessSync(outFile, fs.AccessModeType.EXIST)) {
      throw new Error('产物文件未出现在预期位置 ' + outFile + '，已放弃保存。');
    }
  } catch (e) {
    cleanupStageDir(stageDir);
    removeFileQuiet(outFile);
    throw new Error('表格文件打包失败：' + (e as Error).message);
  }
  cleanupStageDir(stageDir);
  return outFile;
}
