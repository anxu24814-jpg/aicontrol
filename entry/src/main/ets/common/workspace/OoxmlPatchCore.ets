// OOXML 补丁纯核心：docx 正文（word/document.xml）/ xlsx 工作表（xl/worksheets/sheetN.xml）
// / pptx 幻灯片（ppt/slides/slideN.xml）三类部件的字符串级定点改写。★ 本文件零 import、
// 只用 erasable TS 语法（无 enum/namespace/装饰器/参数属性）——scripts/assert-zip-office-domain.mjs
// 把本文件复制为 .ts 由 node 类型剥离直跑，断言的就是线上同一实现（照 ZipArchiveCore /
// SseParser 直跑纪律）。kit IO 面（解包 / 读部件 / 写回 / 重打包 / 吸入落库）全在壳层
// providers/ToolOffice.ets，本件零 IO、string in string out。
// · 锚点纪律：docx/pptx 替换只在**单个文本节点内**（w:t / a:t 是叶子节点，内容不含 '<'）
// ——被排版拆到多个 run 的文字在任一节点里都不完整，不保证命中（hits=0 如实报告，
// 禁静默假成功）；查找与替换都在**转义域**进行（find/replace 明文入、escapeXmlText 后
// 在 XML 串里找），未命中段的原有实体形态逐字保留。
// · xlsx 单元格写入**恒转 inlineStr**（t="inlineStr" + <is><t xml:space="preserve">，
// 免 sharedStrings 部件）——t="s" 共享索引引用态输入亦恒转，**禁改 sharedStrings 表**：
// 改表项会静默改坏同索引引用的其他单元格（任务书 R4 / C2-3.3）。值以 '=' 开头 = 公式态
// 写 <f> 且不写 <v>，打开时由表格软件重算。
// · escapeXmlText / colLetter 与 WorkspaceXlsx.ets 同值第二份（原件模块私有非导出——照
// WorkspaceUtil「与附件域同值的实在此自持第二份，同值由断言对照向量钉一致」先例，C1-R7）。
// · 新建单元格按 OOXML 行序/列序插入（c 须按 r 升序排列——乱序触发 Excel/WPS 修复提示），
// 列序 = 列字母先比长度再比字典序（B < AA）。
// · String.replace 字符串替换形态有 '$&' 等特殊替换模式坑——替换一律走 replaceAllPlain
// 手写 indexOf/splice 拼接，零正则替换。

// 改写结果（note 非空 = 壳层回执需附带说明的边界如实报告）
export interface PatchResult {
  patched: string;      // 改写后的部件 XML 全文
  hits: number;         // 命中/写入计数（替换次数 / 插入段数 / 写入格数）
  note: string;         // 边界说明（空 = 无；公式态 = 重算提示句，与文案总表同文）
}

// XML 文本转义：标准五实体 + 非法控制字符剔除（\t \n \r 是 XML 1.0 合法控制字符保留）
// 〔与 WorkspaceXlsx.ets 同值第二份——同值由 assert-zip-office-domain 496 组对照向量钉〕
export function escapeXmlText(text: string): string {
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
// 〔与 WorkspaceXlsx.ets 同值第二份——同值由 assert-zip-office-domain 496 组对照向量钉〕
export function colLetter(colIndex1: number): string {
  let n: number = colIndex1;
  let s: string = '';
  while (n > 0) {
    const rem: number = (n - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

// 全量替换产物（具名形态——ArkTS 禁匿名对象类型与无接口字面量）
interface ReplaceOutcome {
  out: string;
  count: number;
}

// 全量替换（手写 indexOf 拼接——String.replace 字符串形态有 '$&' 特殊模式坑；空 find
// 死循环防御位：恒 0 次）
function replaceAllPlain(s: string, find: string, rep: string): ReplaceOutcome {
  if (find === '') {
    return { out: s, count: 0 };
  }
  let out: string = '';
  let i: number = 0;
  let count: number = 0;
  while (i <= s.length) {
    const at: number = s.indexOf(find, i);
    if (at < 0) {
      out += s.substring(i);
      break;
    }
    out += s.substring(i, at) + rep;
    i = at + find.length;
    count++;
  }
  return { out: out, count: count };
}

// 文本节点内替换共用体（docx = w:t / pptx = a:t）：只在 <tag>…</tag> / <tag attr>…</tag>
// 的内容区找（转义域），标签本体与属性区永不被触及；hits = 全部节点替换次数累计
function replaceInTextNodes(xml: string, tag: string, find: string,
  replace: string): PatchResult {
  if (find === '') {
    return { patched: xml, hits: 0, note: '查找内容为空，未执行替换。' };
  }
  const findEsc: string = escapeXmlText(find);
  const repEsc: string = escapeXmlText(replace);
  const re: RegExp = new RegExp('<' + tag + '(\\s[^>]*)?>([^<]*)</' + tag + '>', 'g');
  let hits: number = 0;
  const patched: string = xml.replace(re, (m: string, attrs: string,
    content: string): string => {
    const r = replaceAllPlain(content, findEsc, repEsc);
    if (r.count === 0) {
      return m;
    }
    hits += r.count;
    return '<' + tag + (attrs ?? '') + '>' + r.out + '</' + tag + '>';
  });
  return { patched: patched, hits: hits, note: '' };
}

// docx 正文替换：单 w:t 节点内替换（跨 run 拆分文本不保证命中——hits=0 如实报告）
export function docxReplaceTextPart(xml: string, find: string,
  replace: string): PatchResult {
  return replaceInTextNodes(xml, 'w:t', find, replace);
}

// pptx 幻灯片替换：a:t 同构 docx（壳层逐 slide 应用、命中合计）
export function pptxReplaceTextPart(slideXml: string, find: string,
  replace: string): PatchResult {
  return replaceInTextNodes(slideXml, 'a:t', find, replace);
}

// docx 末尾追加最小段（<w:p><w:r><w:t>…）：插在 body 末——正文级 sectPr 在场时插其前
//（sectPr 必须是 body 最后一个子元素，插在它后面触发严格解析器修复提示）；无 sectPr 则
// 插 </w:body> 前。找不到 </w:body> = 不是 docx 正文部件，抛中文。
export function docxAppendParagraphPart(xml: string, text: string): PatchResult {
  const closeAt: number = xml.indexOf('</w:body>');
  if (closeAt < 0) {
    throw new Error('文档部件里找不到正文结束标记，无法追加段落。');
  }
  let at: number = closeAt;
  const sectTail: number = xml.lastIndexOf('</w:sectPr></w:body>');
  if (sectTail >= 0) {
    const sectHead: number = xml.lastIndexOf('<w:sectPr', sectTail);
    if (sectHead >= 0) {
      at = sectHead;
    }
  }
  const para: string = '<w:p><w:r><w:t xml:space="preserve">' +
    escapeXmlText(text) + '</w:t></w:r></w:p>';
  return { patched: xml.substring(0, at) + para + xml.substring(at), hits: 1, note: '' };
}

// cellRef 列字母提取与序比较（B < AA：先长度后字典序）
function colOfRef(cellRef: string): string {
  let i: number = 0;
  while (i < cellRef.length && cellRef.charAt(i) >= 'A' && cellRef.charAt(i) <= 'Z') {
    i++;
  }
  return cellRef.substring(0, i);
}

function colCompare(a: string, b: string): number {
  if (a.length !== b.length) {
    return a.length - b.length;
  }
  return a < b ? -1 : (a > b ? 1 : 0);
}

// 单元格内容构造：公式态（'=' 开头）= <f> 无 <v>（打开时由表格软件重算，note 同文案总表）；
// 其余恒 inlineStr（含空串——写入空文本格）
function buildCellInnerXml(cellRef: string, value: string): string {
  if (value.length > 0 && value.charAt(0) === '=') {
    return '<c r="' + cellRef + '"><f>' + escapeXmlText(value.substring(1)) +
      '</f></c>';
  }
  return '<c r="' + cellRef + '" t="inlineStr"><is><t xml:space="preserve">' +
    escapeXmlText(value) + '</t></is></c>';
}

// row 元素定位产物（具名形态；row 为 null = 不在场）
interface RowSpan {
  start: number;
  end: number;
  selfClosed: boolean;
}

// row 元素定位（返回 null = 不在场；自闭合形态以 selfClosed 标记——空行常见 '<row r="3"/>'）
function locateRow(sheetXml: string, rowNum: number): RowSpan | null {
  const re: RegExp = new RegExp('<row r="' + rowNum + '"(\\s[^>]*)?/?>', 'g');
  const m: RegExpExecArray | null = re.exec(sheetXml);
  if (m === null) {
    return null;
  }
  const start: number = m.index;
  const tagEnd: number = start + m[0].length; // 含 '>' 或 '/>'
  if (m[0].charAt(m[0].length - 1) === '/') {
    return { start: start, end: tagEnd, selfClosed: true }; // '/>' 已含在 m[0]
  }
  // m[0] 以 '>' 收尾——真正的 '>' 在 m[0].length - 1；自闭合判定改看倒数第二字符
  if (m[0].length >= 2 && m[0].charAt(m[0].length - 2) === '/') {
    return { start: start, end: tagEnd, selfClosed: true };
  }
  const closeAt: number = sheetXml.indexOf('</row>', tagEnd);
  if (closeAt < 0) {
    throw new Error('表格部件里行 ' + rowNum + ' 缺少结束标记，结构不完整。');
  }
  return { start: start, end: closeAt + '</row>'.length, selfClosed: false };
}

// row 内容里的列序插入点（返回 insertAt 相对 sheetXml 坐标；无既有 c = 闭标签前）
function rowCellInsertAt(sheetXml: string, rowStart: number, rowEnd: number,
  selfClosed: boolean, targetCol: string): number {
  if (selfClosed) {
    return rowEnd; // 展开形态由调用方重建（'<row r="N"/>' → '<row r="N">' + c + '</row>'）
  }
  const innerEnd: number = sheetXml.indexOf('</row>', rowStart);
  const re: RegExp = /<c r="([A-Z]+)[0-9]+"/g;
  re.lastIndex = rowStart;
  let m: RegExpExecArray | null = re.exec(sheetXml);
  while (m !== null && m.index < innerEnd) {
    if (colCompare(targetCol, m[1]) < 0) {
      return m.index;
    }
    m = re.exec(sheetXml);
  }
  return innerEnd;
}

// xlsx 写单元格：既有 c 原位改写（保留样式等非 r/t 属性、移除旧 t 属性与 v/is/f 内容——
// t="s" 引用态恒转 inlineStr，禁改 sharedStrings 表）；不在场则按行序/列序正确插入
//（row 不在场一并铸造；sheetData 自闭合 '<sheetData/>' 展开兜底）
export function xlsxSetCellPart(sheetXml: string, cellRef: string,
  value: string): PatchResult {
  const refOk: RegExpExecArray | null = /^([A-Z]+)([1-9][0-9]*)$/.exec(cellRef);
  if (refOk === null) {
    throw new Error('单元格地址「' + cellRef + '」不是有效的 A1 形式。');
  }
  const targetCol: string = refOk[1];
  const rowNum: number = Number(refOk[2]);
  // 既有单元格原位改写
  const cellOpen: string = '<c r="' + cellRef + '"';
  const cellAt: number = sheetXml.indexOf(cellOpen);
  if (cellAt >= 0) {
    const tagEnd: number = sheetXml.indexOf('>', cellAt);
    let cellEnd: number;
    let attrEnd: number;
    if (tagEnd >= 0 && sheetXml.charAt(tagEnd - 1) === '/') {
      // 自闭合形态 <c .../>（Excel 空而有样式的格高频形态）：'>' 前一位即 '/'——cellEnd
      // 含整个 '/>'、属性段截到 '/' 之前。禁从 tagEnd 起再向后搜 '/>'：自闭合格的 tagEnd
      // 恰落在自身 '/>' 的 '>' 上，向后搜必错过自身、误吞后方内容或截留孤儿闭标签
      //（修复笔两千零二十 P1，497 组自闭合三例回归守）
      cellEnd = tagEnd + 1;
      attrEnd = tagEnd - 1;
    } else {
      // 普通形态：首个 '</c>' 即本格闭标签（c 的内容模型无嵌套 c，子元素含 <t/> 等
      // 自闭合不影响闭标签定位）；无 '>' 或无 '</c>' = 结构不完整 fail-closed
      const closeAt: number = sheetXml.indexOf('</c>', tagEnd);
      if (tagEnd < 0 || closeAt < 0) {
        throw new Error('表格部件里单元格 ' + cellRef + ' 缺少结束标记，结构不完整。');
      }
      cellEnd = closeAt + '</c>'.length;
      attrEnd = tagEnd;
    }
    // 开标签属性过滤：移除旧 r/t，保留 s（样式）等其余属性
    const attrText: string = sheetXml.substring(cellAt + cellOpen.length, attrEnd);
    const keep: string[] = [];
    for (const kv of attrText.split(/\s+/)) {
      if (kv !== '' && !kv.startsWith('r=') && !kv.startsWith('t=')) {
        keep.push(kv);
      }
    }
    const keepAttrs: string = keep.length > 0 ? ' ' + keep.join(' ') : '';
    const newCellOpen: string = value.length > 0 && value.charAt(0) === '=' ?
      '<c r="' + cellRef + '"' + keepAttrs + '>' :
      '<c r="' + cellRef + '"' + keepAttrs + ' t="inlineStr">';
    const inner: string = value.length > 0 && value.charAt(0) === '=' ?
      '<f>' + escapeXmlText(value.substring(1)) + '</f>' :
      '<is><t xml:space="preserve">' + escapeXmlText(value) + '</t></is>';
    const note: string = value.length > 0 && value.charAt(0) === '=' ?
      '公式已写入。打开时由表格软件重算。' : '';
    return { patched: sheetXml.substring(0, cellAt) + newCellOpen + inner + '</c>' +
      sheetXml.substring(cellEnd), hits: 1, note: note };
  }
  // 单元格不在场——row 在场则列序插入，row 也缺则铸行按行序插入
  const newCell: string = buildCellInnerXml(cellRef, value);
  const note: string = value.length > 0 && value.charAt(0) === '=' ?
    '公式已写入。打开时由表格软件重算。' : '';
  const row = locateRow(sheetXml, rowNum);
  if (row !== null) {
    const rowOpenEnd: number = sheetXml.indexOf('>', row.start) + 1;
    const rowOpenTag: string = sheetXml.substring(row.start, rowOpenEnd)
      .replace(/\/>$/, '>');
    if (row.selfClosed) {
      return { patched: sheetXml.substring(0, row.start) + rowOpenTag + newCell +
        '</row>' + sheetXml.substring(row.end), hits: 1, note: note };
    }
    const at: number = rowCellInsertAt(sheetXml, row.start, row.end, false, targetCol);
    return { patched: sheetXml.substring(0, at) + newCell + sheetXml.substring(at),
      hits: 1, note: note };
  }
  const newRow: string = '<row r="' + rowNum + '">' + newCell + '</row>';
  const selfClosedSd: number = sheetXml.indexOf('<sheetData/>');
  if (selfClosedSd >= 0) {
    return { patched: sheetXml.substring(0, selfClosedSd) + '<sheetData>' + newRow +
      '</sheetData>' + sheetXml.substring(selfClosedSd + '<sheetData/>'.length),
      hits: 1, note: note };
  }
  const sdOpen: number = sheetXml.indexOf('<sheetData');
  if (sdOpen < 0) {
    throw new Error('表格部件里找不到数据区，无法写入单元格。');
  }
  // 行序插入点 = 第一个行号大于目标的 row 前；无则在 </sheetData> 前
  const re: RegExp = /<row r="([0-9]+)"/g;
  let m: RegExpExecArray | null = re.exec(sheetXml);
  let at: number = -1;
  while (m !== null) {
    if (Number(m[1]) > rowNum) {
      at = m.index;
      break;
    }
    m = re.exec(sheetXml);
  }
  if (at < 0) {
    const closeAt: number = sheetXml.indexOf('</sheetData>');
    if (closeAt < 0) {
      throw new Error('表格部件里数据区缺少结束标记，无法写入单元格。');
    }
    at = closeAt;
  }
  return { patched: sheetXml.substring(0, at) + newRow + sheetXml.substring(at),
    hits: 1, note: note };
}

// xlsx 追加行：现最大行号 +1（显式 <row r="N"> 全扫取 max——行号不要求连续，跳行表
// 追加到末行后）；值恒 inlineStr，空串省略节点（照 WorkspaceXlsx.cellXml 先例）；空
// sheetData（自闭合 '<sheetData/>' 形态）展开兜底
export function xlsxAppendRowPart(sheetXml: string, values: string[]): PatchResult {
  let maxRow: number = 0;
  const re: RegExp = /<row r="([0-9]+)"/g;
  let m: RegExpExecArray | null = re.exec(sheetXml);
  while (m !== null) {
    const n: number = Number(m[1]);
    if (n > maxRow) {
      maxRow = n;
    }
    m = re.exec(sheetXml);
  }
  const rowNum: number = maxRow + 1;
  let cells: string = '';
  let hits: number = 0;
  for (let i: number = 0; i < values.length; i++) {
    if (values[i] === '') {
      continue;
    }
    cells += '<c r="' + colLetter(i + 1) + rowNum +
      '" t="inlineStr"><is><t xml:space="preserve">' + escapeXmlText(values[i]) +
      '</t></is></c>';
    hits++;
  }
  const rowXml: string = '<row r="' + rowNum + '">' + cells + '</row>';
  const closeAt: number = sheetXml.indexOf('</sheetData>');
  if (closeAt >= 0) {
    return { patched: sheetXml.substring(0, closeAt) + rowXml +
      sheetXml.substring(closeAt), hits: hits, note: '' };
  }
  const selfClosedSd: number = sheetXml.indexOf('<sheetData/>');
  if (selfClosedSd >= 0) {
    return { patched: sheetXml.substring(0, selfClosedSd) + '<sheetData>' + rowXml +
      '</sheetData>' + sheetXml.substring(selfClosedSd + '<sheetData/>'.length),
      hits: hits, note: '' };
  }
  throw new Error('表格部件里找不到数据区结束标记，无法追加行。');
}
