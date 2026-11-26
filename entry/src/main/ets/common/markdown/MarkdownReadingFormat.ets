/** 阅读域纯投影。原文出口保源片段，CSV 取语义，局部窗口只物化当前页。 */
import { AI_CONTENT_LABEL } from '../AiDisclosure';
import { MarkdownNode, markdownNode } from './MarkdownSemanticModel';

export const MARKDOWN_READING_ROWS: number = 32;
export const MARKDOWN_READING_COLUMNS: number = 8;
export const MARKDOWN_READING_LEAVES: number = 32;
export const MARKDOWN_READING_UNITS: number = 4096;

export interface MarkdownReadingTablePage {
  rowIndices: number[];
  columnIndices: number[];
  rowPage: number;
  columnPage: number;
  rowCount: number;
  columnCount: number;
  error: string;
}

/** 表格结构校验结论（columns = 合法列数；error 为空串表示结构合法）。 */
export interface MarkdownTableShape {
  columns: number;
  error: string;
}

export interface MarkdownReadingCellWindow {
  nodes: MarkdownNode[];
  page: number;
  hasNext: boolean;
  leafCount: number;
  utf16Units: number;
  imageMetadataUnits: number;
  nodeVisits: number;
}

export function markdownReadingRaw(source: string, node: MarkdownNode): string {
  const start: number = node.range.start;
  const end: number = node.range.end;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start ||
    end > source.length) {
    throw new Error('内容源范围异常，无法复制原文');
  }
  return source.substring(start, end);
}

/** 不引用显示投影：公式不带“公式”标签，换行/空格/空值不 trim。 */
export function markdownReadingSemanticText(node: MarkdownNode): string {
  if (node.kind === 'softBreak' || node.kind === 'hardBreak') {
    return '\n';
  }
  if (node.kind === 'footnoteReference') {
    return '[^' + node.label + ']';
  }
  if (node.kind === 'image' || node.kind === 'math' || node.kind === 'mathBlock' ||
    node.children.length === 0) {
    if (node.text !== '' || node.parts.length === 0) {
      return node.text;
    }
    return node.parts.map((part): string => part.text).join('');
  }
  return node.children.map((child: MarkdownNode): string => markdownReadingSemanticText(child)).join('');
}

function tableColumns(node: MarkdownNode): number {
  if (node.kind !== 'table') {
    throw new Error(TABLE_SHAPE_ERROR);
  }
  if (node.children.length === 0) {
    return 0;
  }
  const columns: number = node.children[0].children.length;
  for (const row of node.children) {
    const error: string = tableRowShapeError(row, columns);
    if (error !== '') {
      throw new Error(error);
    }
  }
  return columns;
}

// 表格结构校验的判据与文案单源（全量与增量两条路径同用）
const TABLE_SHAPE_ERROR: string = '表格结构异常，已回退原文。CSV 暂不可用';
const TABLE_ROW_ERROR: string = '表格行列结构异常，已回退原文。CSV 暂不可用';
const TABLE_CELL_ERROR: string = '表格单元格结构异常，已回退原文。CSV 暂不可用';

/** 单行结构校验（空串 = 合法）：行种类/格数与全表列数一致、每格是单元格。 */
function tableRowShapeError(row: MarkdownNode, columns: number): string {
  if (row.kind !== 'tableRow' || row.children.length !== columns) {
    return TABLE_ROW_ERROR;
  }
  for (const cell of row.children) {
    if (cell.kind !== 'tableCell') {
      return TABLE_CELL_ERROR;
    }
  }
  return '';
}

/** 表格结构增量校验器（构造于渲染件、随组件生命周期释放）：行只在表尾追加——已校验的
 *  非末行不再变化，故按「已校验行数」水位推进，每拍只重校验上一拍末行+新追加行，全表成本
 *  不随表长重付。非 memoization——判据是已校验行数水位而非 children.length/range.end 缓存键。
 *  表身份/列数变化或行数缩短 → 水位归零全量重来；非法行只记账到该行，下拍从该行重验。 */
export class MarkdownTableShapeCheck {
  private tableId: number = 0;
  private checkedRows: number = 0;
  private columns: number = 0;

  verify(node: MarkdownNode): MarkdownTableShape {
    if (node.kind !== 'table') {
      return { columns: 0, error: TABLE_SHAPE_ERROR };
    }
    const rows: MarkdownNode[] = node.children;
    const columns: number = rows.length > 0 ? rows[0].children.length : 0;
    if (node.id !== this.tableId || rows.length < this.checkedRows || columns !== this.columns) {
      this.tableId = node.id;
      this.checkedRows = 0;
      this.columns = columns;
    }
    // 水位回退一行：上一拍末行可能仍在增长（新格/新内容已由块解析落进本拍节点）
    let index: number = this.checkedRows > 0 ? this.checkedRows - 1 : 0;
    for (; index < rows.length; index++) {
      const error: string = tableRowShapeError(rows[index], columns);
      if (error !== '') {
        this.checkedRows = index;
        return { columns: 0, error: error };
      }
    }
    this.checkedRows = rows.length;
    this.columns = columns;
    return { columns: columns, error: '' };
  }
}

function csvRecord(fields: string[]): string {
  return fields.map((field: string): string => '"' + field.replace(/"/g, '""') + '"').join(',');
}

export function markdownReadingCsv(node: MarkdownNode, aiContent: boolean = true): string {
  const columns: number = tableColumns(node);
  if (columns === 0) {
    throw new Error('表格没有列，无法导出 CSV');
  }
  const records: string[] = node.children.map((row: MarkdownNode): string =>
    csvRecord(row.children.map((cell: MarkdownNode): string => markdownReadingSemanticText(cell))));
  const notice: string[] = [];
  for (let column: number = 0; column < columns; column++) {
    notice.push(column === 0 ? AI_CONTENT_LABEL : '');
  }
  if (aiContent) { records.push(csvRecord(notice)); }
  return records.join('\r\n');
}

function safePage(page: number, maximum: number): number {
  return Number.isSafeInteger(page) ? Math.max(0, Math.min(page, maximum)) : 0;
}

export function markdownReadingTablePage(node: MarkdownNode, rowPage: number,
  columnPage: number, shape: MarkdownTableShapeCheck | undefined = undefined): MarkdownReadingTablePage {
  let columns: number = 0;
  let error: string = '';
  if (shape !== undefined) {
    // 增量校验：渲染件持增量器跨拍续验，只重验末行与新行。
    const checked: MarkdownTableShape = shape.verify(node);
    columns = checked.columns;
    error = checked.error;
  } else {
    try {
      // 无增量器（旁路/直跑）时显式全扫描所有行/格，不冒称增量。
      columns = tableColumns(node);
    } catch (failure) {
      error = (failure as Error).message;
    }
  }
  const rows: number = Math.max(0, node.children.length - 1);
  const currentRow: number = safePage(rowPage, Math.max(0, Math.ceil(rows / MARKDOWN_READING_ROWS) - 1));
  const currentColumn: number = safePage(columnPage,
    Math.max(0, Math.ceil(columns / MARKDOWN_READING_COLUMNS) - 1));
  const rowIndices: number[] = [];
  const columnIndices: number[] = [];
  if (error === '' && columns > 0) {
    rowIndices.push(0);
    for (let index: number = 1 + currentRow * MARKDOWN_READING_ROWS;
      index < Math.min(node.children.length, 1 + (currentRow + 1) * MARKDOWN_READING_ROWS); index++) {
      rowIndices.push(index);
    }
    for (let index: number = currentColumn * MARKDOWN_READING_COLUMNS;
      index < Math.min(columns, (currentColumn + 1) * MARKDOWN_READING_COLUMNS); index++) {
      columnIndices.push(index);
    }
  }
  return { rowIndices: rowIndices, columnIndices: columnIndices, rowPage: currentRow,
    columnPage: currentColumn, rowCount: rows, columnCount: columns, error: error };
}

export function markdownReadingTitle(node: MarkdownNode): string {
  if (node.kind === 'table') {
    if (node.children.length > 0 && node.children[0].children.length > 0) {
      const cell: MarkdownReadingCellWindow = markdownReadingCellWindow(node.children[0].children[0], 0);
      const title: string = cell.nodes.map((part: MarkdownNode): string => markdownReadingSemanticText(part))
        .join('').replace(/\s+/g, ' ').trim().substring(0, 24);
      if (title !== '') {
        return title + ' · 表格';
      }
    }
    return '表格';
  }
  if (node.kind === 'htmlBlock') { return 'HTML 源码'; }
  // 块级公式不经阅读壳挂载（直挂 MarkdownMath）——本函数零公式分支，消费方 MarkdownScrollableBlock 亦不收公式。
  const label: string = node.language !== '' ? node.language : '代码';
  return label + (node.closed ? ' · 已闭合' : ' · 未闭合');
}

interface ReadingStyle {
  bold: boolean;
  italic: boolean;
  strike: boolean;
  mark: boolean;
  script: number;
  destination: string;
}

interface ReadingCursor {
  nodes: MarkdownNode[];
  index: number;
  style: ReadingStyle;
}

function withStyle(style: ReadingStyle, node: MarkdownNode): ReadingStyle {
  return { bold: style.bold || node.kind === 'strong', italic: style.italic || node.kind === 'emphasis',
    strike: style.strike || node.kind === 'strikethrough',
    mark: style.mark || node.kind === 'highlight',
    script: node.kind === 'subscript' ? -1 : node.kind === 'superscript' ? 1 : style.script,
    destination: node.kind === 'link' ? node.destination : style.destination };
}

function styledLeaf(node: MarkdownNode, text: string, style: ReadingStyle, id: number): MarkdownNode {
  // 只克隆选中的叶片，祖先修饰按有效样式重建至多五层，深层容器不膨胀 UI 树。
  // 数学、脚注与图片是原子语义，不能切碎公式或把引用改成失去跳转目标的普通文字。
  let result: MarkdownNode = markdownNode(node.kind, node.range.start, node.range.end);
  result.id = id;
  result.text = text;
  result.destination = node.destination;
  result.title = node.title;
  result.label = node.label;
  result.closed = node.closed;
  result.startNumber = node.startNumber;
  const kinds: string[] = [];
  if (style.bold) { kinds.push('strong'); }
  if (style.italic) { kinds.push('emphasis'); }
  if (style.strike) { kinds.push('strikethrough'); }
  if (style.mark) { kinds.push('highlight'); }
  if (style.script !== 0) { kinds.push(style.script < 0 ? 'subscript' : 'superscript'); }
  if (style.destination !== '') { kinds.push('link'); }
  for (const kind of kinds) {
    const wrapper: MarkdownNode = markdownNode(kind === 'strong' ? 'strong' : kind === 'emphasis' ? 'emphasis' :
      kind === 'strikethrough' ? 'strikethrough' : kind === 'highlight' ? 'highlight' :
      kind === 'subscript' ? 'subscript' :
      kind === 'superscript' ? 'superscript' : 'link', node.range.start, node.range.end);
    wrapper.id = id;
    wrapper.destination = kind === 'link' ? style.destination : '';
    wrapper.children = [result];
    result = wrapper;
  }
  return result;
}

function safeTextEnd(text: string, start: number, capacity: number): number {
  let end: number = Math.min(text.length, start + capacity);
  if (end < text.length && end > start) {
    const left: number = text.charCodeAt(end - 1);
    const right: number = text.charCodeAt(end);
    if (left >= 0xD800 && left <= 0xDBFF && right >= 0xDC00 && right <= 0xDFFF) { end--; }
  }
  return end;
}

/**
 * 从根走到目标窗+一片前瞻即停（不 inlineRuns 全树后 slice、不建全页列表）。图片为原子
 * 资源，URL/alt 不截断、不占文本预算；其余文字每窗 <=4096 UTF16、<=32 叶片；祖先格式保留。
 * nodeVisits 是本次真实访问，翻后页需重扫前缀，不是 O(1)。
 */
export function markdownReadingCellWindow(node: MarkdownNode, requestedPage: number,
  referenceId: number = 0): MarkdownReadingCellWindow {
  let target: number = referenceId > 0 ? Number.MAX_SAFE_INTEGER :
    Number.isSafeInteger(requestedPage) ? Math.max(0, requestedPage) : 0;
  let metadataUnits: number = 0;
  const initial: ReadingStyle = { bold: false, italic: false, strike: false, mark: false, script: 0, destination: '' };
  const stack: ReadingCursor[] = [{ nodes: node.children.length > 0 ? node.children : [node],
    index: 0, style: initial }];
  let page: number = 0;
  let leaves: number = 0;
  let units: number = 0;
  let visits: number = 0;
  let id: number = 0;
  let result: MarkdownNode[] = [];
  while (stack.length > 0) {
    const cursor: ReadingCursor = stack[stack.length - 1];
    if (cursor.index >= cursor.nodes.length) { stack.pop(); continue; }
    const leaf: MarkdownNode = cursor.nodes[cursor.index++];
    visits++;
    const style: ReadingStyle = withStyle(cursor.style, leaf);
    if (leaf.children.length > 0 && leaf.kind !== 'image') {
      stack.push({ nodes: leaf.children, index: 0, style: style });
      continue;
    }
    const atomic: boolean = leaf.kind === 'image' || leaf.kind === 'math' || leaf.kind === 'mathBlock' ||
      leaf.kind === 'footnoteReference' || leaf.kind === 'htmlInline';
    const text: string = atomic ? leaf.text : markdownReadingSemanticText(leaf);
    let offset: number = 0;
    let first: boolean = true;
    while (first || offset < text.length) {
      first = false;
      let end: number = atomic ? text.length :
        safeTextEnd(text, offset, MARKDOWN_READING_UNITS - units);
      if (leaves >= MARKDOWN_READING_LEAVES ||
        (!atomic && (units >= MARKDOWN_READING_UNITS || (end === offset && text.length > offset)))) {
        if (page === target) {
          return { nodes: result, page: page, hasNext: true, leafCount: leaves,
            utf16Units: units, imageMetadataUnits: metadataUnits, nodeVisits: visits };
        }
        page++;
        leaves = 0;
        units = 0;
        metadataUnits = 0;
        result = [];
        end = atomic ? text.length : safeTextEnd(text, offset, MARKDOWN_READING_UNITS);
      }
      const fragment: string = text.substring(offset, end);
      id++;
      if (referenceId > 0 && leaf.id === referenceId) {
        return markdownReadingCellWindow(node, page);
      }
      if (page === target) {
        result.push(styledLeaf(leaf, fragment, style, atomic ? leaf.id : -id));
      }
      leaves++;
      units += atomic ? 0 : fragment.length;
      metadataUnits += atomic ? leaf.text.length + leaf.destination.length +
        leaf.title.length + style.destination.length : 0;
      offset = end;
    }
  }
  if (page < target) {
    // 异常越界请求只重读实际最后一窗，不缓存历史页。正常“下一部分”由 hasNext 保证可达。
    const last: MarkdownReadingCellWindow = markdownReadingCellWindow(node, page);
    last.nodeVisits += visits;
    return last;
  }
  return { nodes: result, page: page, hasNext: false, leafCount: leaves,
    utf16Units: units, imageMetadataUnits: metadataUnits, nodeVisits: visits };
}
