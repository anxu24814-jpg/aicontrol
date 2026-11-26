/**
 * CommonMark 块容器栈 + 本项目表格/数学/脚注扩展，不解析行内、不执行 HTML。
 * 开放叶块先消费已匹配容器内的行；只有开放段落允许惰性续行。最大64层容器，
 * 超限标记作为段落保留。parsedUnits 包括失败探测、重扫与子串/连接物化，非线性承诺。
 */
import { MarkdownNode, MarkdownSemanticWork, MarkdownTextSlice, markdownNode } from './MarkdownSemanticModel';
import { decodeMarkdownEntities } from './MarkdownEntities';
import { MarkdownBlockLine, BlockFence, BlockListMarker, BlockHeading, BlockMath, BlockCells, BlockDefinition,
  blockChar, blockSlice, blockJoin, blockSpace, blockLines, blockView, blockIndent, blockStrip, blockAfter,
  blockBlank, blockTrimEnd, blockLiteral, blockQuote, blockList, blockRule, blockSetext, blockAtx, blockFence,
  blockFenceClose, blockToc, blockMath, blockMathClose, blockHtml, blockHtmlClose, blockCells,
  blockAlignments, blockLabel, blockDefinition } from './MarkdownBlockScan';

const MAX_BLOCK_DEPTH: number = 64;
// ── latex 围栏旁路（U7-R4b；别名集 U7-R4c 扩）──
// ```latex / ```tex / ```math / ```katex / ```mathjax 围栏按公式通道渲染（用户拍板「部分 latex
// 显示为代码块样式，都改成直接内嵌显示」）：开行即产出 mathBlock 节点，围栏体进 literals 走
// 既有 LaTeX→位图管线（MarkdownMath）与失败/超限兜底，闭合只翻 closed 不换 kind——语义身份 =
// 种类 + 源起点（MarkdownSemanticDocument.identityKey），闭合帧不换 id，规避整块子树重建
//（方案档 CRIT2 F5）。别名集是唯一判据，不做内容特征启发式（不可测、行为不可预期）；
// MARKDOWN_LATEX_FENCE_ENABLED 置 false 回纯代码块现状（回退通道）。
export const MARKDOWN_LATEX_FENCE_ENABLED: boolean = true;
// 别名集（单源）：围栏 info 首词小写比对（与 MarkdownPreviewPolicy 语言判定同口径：
// trim + toLowerCase），逐词全等比中才转公式通道。
const MARKDOWN_LATEX_FENCE_LANGUAGES: string[] = ['latex', 'tex', 'math', 'katex', 'mathjax'];
function markdownLatexFenceLanguage(language: string): boolean {
  return MARKDOWN_LATEX_FENCE_LANGUAGES.indexOf(language.trim().toLowerCase()) >= 0;
}
class BlockFrame {
  node: MarkdownNode;
  indent: number = 0;
  marker: string = '';
  fence: BlockFence | undefined = undefined;
  htmlType: number = 0;
  closer: string = '';
  lines: MarkdownBlockLine[] = [];
  literals: string[] = [];
  emptyItem: boolean = false;
  constructor(node: MarkdownNode) { this.node = node; }
}
function container(frame: BlockFrame): boolean {
  return frame.node.kind === 'blockquote' || frame.node.kind === 'list' || frame.node.kind === 'listItem' ||
    frame.node.kind === 'footnoteDefinition';
}
function sourceStart(line: MarkdownBlockLine): number { return line.offset + line.position - (line.extra > 0 ? 1 : 0); }
function sourceEnd(line: MarkdownBlockLine): number { return line.offset + line.end; }
function punctuation(character: string): boolean {
  const code: number = character.charCodeAt(0);
  return (code >= 33 && code <= 47) || (code >= 58 && code <= 64) ||
    (code >= 91 && code <= 96) || (code >= 123 && code <= 126);
}
function decodeBlockValue(value: string, work: MarkdownSemanticWork): string {
  // Escaped ampersands must not be reinterpreted as entities. Decode unescaped runs separately.
  const output: string[] = [];
  let start: number = 0;
  for (let index: number = 0; index < value.length; index++) {
    if (blockChar(value, index, work) !== '\\' || !punctuation(blockChar(value, index + 1, work))) { continue; }
    const run: string = blockSlice(value, start, index, work);
    work.parsedUnits += run.length; work.materializedUnits += run.length;
    output.push(decodeMarkdownEntities(run)); output.push(blockChar(value, ++index, work)); start = index + 1;
  }
  const run: string = blockSlice(value, start, value.length, work);
  work.parsedUnits += run.length; work.materializedUnits += run.length;
  output.push(decodeMarkdownEntities(run));
  return blockJoin(output, work);
}
function addSlice(node: MarkdownNode, line: MarkdownBlockLine, start: number, end: number, work: MarkdownSemanticWork): void {
  if (end > start) { node.parts.push({ text: blockSlice(line.source, start, end, work), start: line.offset + start }); }
}
function paragraphParts(node: MarkdownNode, lines: MarkdownBlockLine[], work: MarkdownSemanticWork): void {
  node.parts = [];
  for (let index: number = 0; index < lines.length; index++) {
    const line: MarkdownBlockLine = lines[index];
    const start: number = blockIndent(line, work).position;
    const end: number = index === lines.length - 1 ? Math.max(start, blockTrimEnd(line, line.bodyEnd, work)) : line.bodyEnd;
    addSlice(node, line, start, end, work);
    if (index + 1 < lines.length) { addSlice(node, line, line.bodyEnd, line.end, work); }
  }
}
function headingId(node: MarkdownNode, work: MarkdownSemanticWork): void {
  if (node.parts.length === 0) { return; }
  const part: MarkdownTextSlice = node.parts[node.parts.length - 1];
  const value: string = part.text;
  if (blockChar(value, value.length - 1, work) !== '}') { return; }
  let start: number = value.length - 2;
  while (start >= 0) {
    const character: string = blockChar(value, start, work);
    if (character === '{') { break; }
    if (blockSpace(character) || character === '\n' || character === '\r' || character === '}') { return; }
    start--;
  }
  if (start < 0 || blockChar(value, start + 1, work) !== '#' || start + 2 === value.length - 1 ||
    (start > 0 && !blockSpace(blockChar(value, start - 1, work)))) { return; }
  node.headingId = blockSlice(value, start + 2, value.length - 1, work); node.label = node.headingId;
  while (start > 0 && blockSpace(blockChar(value, start - 1, work))) { start--; }
  part.text = blockSlice(value, 0, start, work);
  if (part.text.length === 0) { node.parts.pop(); }
}
function taskPrefix(item: MarkdownNode, work: MarkdownSemanticWork): void {
  let first: number = 0;
  while (first < item.children.length && item.children[first].kind === 'blank') { first++; }
  if (first === item.children.length || item.children[first].kind !== 'paragraph') { return; }
  const paragraph: MarkdownNode = item.children[first];
  if (paragraph.parts.length === 0) { return; }
  const part: MarkdownTextSlice = paragraph.parts[0];
  const text: string = part.text;
  const check: string = blockChar(text, 1, work);
  if (blockChar(text, 0, work) !== '[' || blockChar(text, 2, work) !== ']' ||
    (check !== ' ' && check !== 'x' && check !== 'X') || (text.length > 3 && !blockSpace(blockChar(text, 3, work)))) { return; }
  item.checked = check !== ' ';
  let position: number = 3;
  while (position < text.length && blockSpace(blockChar(text, position, work))) { position++; }
  part.text = blockSlice(text, position, text.length, work); part.start += position;
  if (part.text.length === 0) { paragraph.parts.shift(); }
}
function endsBlank(node: MarkdownNode): boolean {
  if (node.kind === 'blank') { return true; }
  if (node.kind !== 'list' && node.kind !== 'listItem') { return false; }
  return node.children.length > 0 && endsBlank(node.children[node.children.length - 1]);
}
function listTight(node: MarkdownNode): void {
  for (let index: number = 0; index < node.children.length; index++) {
    const item: MarkdownNode = node.children[index];
    if (index + 1 < node.children.length && endsBlank(item)) { node.tight = false; }
    let seen: boolean = false;
    let blank: boolean = false;
    for (let child: number = 0; child < item.children.length; child++) {
      const block: MarkdownNode = item.children[child];
      if (block.kind === 'blank') { if (seen) { blank = true; } continue; }
      if (seen && blank) { node.tight = false; }
      seen = true; blank = endsBlank(block);
    }
  }
  for (let index: number = 0; index < node.children.length; index++) { node.children[index].tight = node.tight; }
}

class MarkdownBlockParser {
  work: MarkdownSemanticWork;
  frames: BlockFrame[];
  constructor(offset: number, work: MarkdownSemanticWork) {
    this.work = work; this.frames = [new BlockFrame(markdownNode('blockquote', offset, offset))];
  }
  top(): BlockFrame { return this.frames[this.frames.length - 1]; }
  touch(line: MarkdownBlockLine): void {
    for (let index: number = 0; index < this.frames.length; index++) {
      this.work.nodeVisits++; this.frames[index].node.range.end = sourceEnd(line);
    }
  }
  push(node: MarkdownNode): BlockFrame {
    this.top().node.children.push(node);
    const frame: BlockFrame = new BlockFrame(node);
    this.frames.push(frame); this.work.nodeVisits++;
    return frame;
  }
  leaf(node: MarkdownNode, line: MarkdownBlockLine): void {
    this.top().node.children.push(node); this.work.nodeVisits++; this.touch(line);
  }
  splitDefinitions(frame: BlockFrame): void {
    const parent: MarkdownNode = this.frames[this.frames.length - 2].node;
    let first: number = 0;
    const definitions: MarkdownNode[] = [];
    while (first < frame.lines.length) {
      const definition: BlockDefinition | undefined = blockDefinition(frame.lines, first, this.work);
      if (definition === undefined) { break; }
      definition.node.range.start = first === 0 ? frame.node.range.start : sourceStart(frame.lines[first]);
      definition.node.destination = decodeBlockValue(definition.node.destination, this.work);
      definition.node.title = decodeBlockValue(definition.node.title, this.work);
      definitions.push(definition.node); first += definition.consumed;
    }
    if (first === 0) { return; }
    parent.children.pop();
    for (let index: number = 0; index < definitions.length; index++) { parent.children.push(definitions[index]); }
    frame.lines = frame.lines.slice(first);
    if (frame.lines.length > 0) {
      frame.node.range.start = sourceStart(frame.lines[0]); parent.children.push(frame.node);
    }
  }
  close(): void {
    const frame: BlockFrame = this.top();
    if (frame.node.kind === 'paragraph') {
      this.splitDefinitions(frame);
      if (frame.lines.length > 0) { paragraphParts(frame.node, frame.lines, this.work); }
    } else if (frame.node.kind === 'codeBlock' || frame.node.kind === 'mathBlock' || frame.node.kind === 'htmlBlock') {
      frame.node.text = blockJoin(frame.literals, this.work);
    } else if (frame.node.kind === 'listItem') { taskPrefix(frame.node, this.work); }
    else if (frame.node.kind === 'list') { listTight(frame.node); }
    this.frames.pop();
    // Blank lines after indented code belong to its parent, not the code literal.
    if (frame.node.kind === 'codeBlock' && frame.fence === undefined) {
      for (let index: number = 0; index < frame.lines.length; index++) {
        const line: MarkdownBlockLine = frame.lines[index];
        this.leaf(markdownNode('blank', sourceStart(line), sourceEnd(line)), line);
      }
    }
  }
  closeTo(length: number): void { while (this.frames.length > length) { this.close(); } }
  interrupt(line: MarkdownBlockLine): boolean {
    if (blockIndent(line, this.work).columns > 3) { return false; }
    if (blockQuote(line, this.work) !== undefined || blockAtx(line, this.work) !== undefined ||
      blockFence(line, this.work) !== undefined || blockRule(line, this.work)) { return true; }
    const list: BlockListMarker | undefined = blockList(line, this.work);
    if (list !== undefined && !list.empty && (!list.ordered || list.number === 1)) { return true; }
    const html: number = blockHtml(line, this.work);
    return (html > 0 && html < 7) || blockToc(line, this.work) || blockMath(line, this.work) !== undefined ||
      blockLabel(line, true, this.work) !== undefined;
  }
  match(line: MarkdownBlockLine): MarkdownBlockLine {
    let view: MarkdownBlockLine = blockView(line);
    let matched: number = 1;
    while (matched < this.frames.length && container(this.frames[matched])) {
      const frame: BlockFrame = this.frames[matched];
      if (frame.node.kind === 'blockquote') {
        const next: MarkdownBlockLine | undefined = blockQuote(view, this.work);
        if (next === undefined) { break; }
        view = next;
      } else if (frame.node.kind === 'listItem' || frame.node.kind === 'footnoteDefinition') {
        if (blockBlank(view, this.work)) {
          if (frame.emptyItem) { break; }
          // A blank continuation satisfies a list item without preserving its indentation as code.
          view = blockAfter(view, view.bodyEnd, this.work);
        } else if (blockIndent(view, this.work).columns >= frame.indent) {
          view = blockStrip(view, frame.indent, this.work); frame.emptyItem = false;
        } else { break; }
      }
      matched++;
    }
    if (matched < this.frames.length && container(this.frames[matched])) {
      const last: BlockFrame = this.top();
      // Once an outer container fails, a list starts a sibling even with a non-1 start or empty item.
      const sibling: boolean = blockList(view, this.work) !== undefined;
      if (!sibling && last.node.kind === 'paragraph' && !blockBlank(view, this.work) && !this.interrupt(view)) {
        // Definitions stay provisional paragraph content until closure, including lazy title lines.
        // A missing marker cannot introduce setext/table syntax, only paragraph continuation.
        last.lines.push(view); this.touch(line);
        return new MarkdownBlockLine('', 0, 0, 0, -1);
      }
      this.closeTo(matched);
    }
    return view;
  }
  row(table: MarkdownNode, line: MarkdownBlockLine, cells: MarkdownTextSlice[]): void {
    const row: MarkdownNode = markdownNode('tableRow', sourceStart(line), sourceEnd(line));
    for (let index: number = 0; index < table.alignments.length; index++) {
      const part: MarkdownTextSlice = index < cells.length ? cells[index] : { text: '', start: line.offset + line.bodyEnd };
      const cell: MarkdownNode = markdownNode('tableCell', part.start, part.start + part.text.length);
      if (part.text.length > 0) { cell.parts.push(part); }
      row.children.push(cell); this.work.nodeVisits++;
    }
    table.children.push(row); this.work.nodeVisits++;
  }
  continueLeaf(line: MarkdownBlockLine): boolean {
    const frame: BlockFrame = this.top();
    const kind: string = frame.node.kind;
    // 围栏体消费面（codeBlock + U7-R4b latex 旁路的 mathBlock）：闭合认 blockFenceClose、内容
    // 认去开栏缩进，两 kind 同形——latex 围栏的 closed 只在此翻转，kind 全程不变。
    if (frame.fence !== undefined && (kind === 'codeBlock' || kind === 'mathBlock')) {
      if (blockFenceClose(line, frame.fence, this.work)) {
        frame.node.closed = true; this.touch(line); this.close();
      } else { frame.literals.push(blockLiteral(blockStrip(line, frame.fence.indent, this.work), this.work)); this.touch(line); }
      return true;
    }
    if (kind === 'mathBlock') {
      if (blockMathClose(line, frame.closer, this.work)) { frame.node.closed = true; this.touch(line); this.close(); }
      else { frame.literals.push(blockLiteral(line, this.work)); this.touch(line); }
      return true;
    }
    if (kind === 'htmlBlock') {
      if (frame.htmlType >= 6 && blockBlank(line, this.work)) { this.close(); return false; }
      frame.literals.push(blockLiteral(line, this.work)); this.touch(line);
      if (blockHtmlClose(line, frame.htmlType, this.work)) { frame.node.closed = true; this.close(); }
      return true;
    }
    if (kind === 'codeBlock') {
      if (blockBlank(line, this.work)) {
        frame.lines.push(blockView(line));
        for (let index: number = 0; index + 1 < this.frames.length; index++) { this.frames[index].node.range.end = sourceEnd(line); }
        return true;
      }
      if (blockIndent(line, this.work).columns >= 4) {
        for (let index: number = 0; index < frame.lines.length; index++) {
          frame.literals.push(blockLiteral(blockStrip(frame.lines[index], 4, this.work), this.work));
        }
        frame.lines = []; frame.literals.push(blockLiteral(blockStrip(line, 4, this.work), this.work)); this.touch(line); return true;
      }
      this.close(); return false;
    }
    if (kind === 'table') {
      if (blockBlank(line, this.work) || this.interrupt(line)) { this.close(); return false; }
      const cells: BlockCells = blockCells(line, this.work);
      // A row with no separator is a one-cell short row; blank/new block ends the table.
      this.row(frame.node, line, cells.cells); this.touch(line); return true;
    }
    if (kind !== 'paragraph') { return false; }
    if (blockBlank(line, this.work)) { this.close(); return false; }
    const level: number = blockSetext(line, this.work);
    if (level > 0) {
      this.splitDefinitions(frame);
      if (frame.lines.length === 0) { this.frames.pop(); return false; }
      frame.node.kind = 'heading'; frame.node.level = level;
      paragraphParts(frame.node, frame.lines, this.work); headingId(frame.node, this.work);
      this.touch(line); this.close(); return true;
    }
    if (frame.lines.length === 1 && blockIndent(line, this.work).columns <= 3) {
      const delimiter: BlockCells = blockCells(line, this.work);
      const alignments: string[] | undefined = blockAlignments(delimiter.cells, this.work);
      if (alignments !== undefined) {
        const header: BlockCells = blockCells(frame.lines[0], this.work);
        if (header.cells.length === alignments.length && (header.pipes > 0 || delimiter.pipes > 0)) {
          frame.node.kind = 'table'; frame.node.alignments = alignments;
          this.row(frame.node, frame.lines[0], header.cells); frame.lines = [];
          this.touch(line); return true;
        }
      }
    }
    if (this.interrupt(line)) { this.close(); return false; }
    frame.lines.push(blockView(line)); this.touch(line); return true;
  }
  openList(line: MarkdownBlockLine, marker: BlockListMarker): MarkdownBlockLine {
    let list: BlockFrame = this.top();
    if (list.node.kind === 'list' && (list.marker !== marker.character || list.node.ordered !== marker.ordered)) { this.close(); list = this.top(); }
    if (list.node.kind !== 'list') {
      const node: MarkdownNode = markdownNode('list', sourceStart(line), sourceEnd(line));
      node.ordered = marker.ordered; node.startNumber = marker.number;
      list = this.push(node); list.marker = marker.character;
    }
    const item: BlockFrame = this.push(markdownNode('listItem', sourceStart(line), sourceEnd(line)));
    item.indent = marker.indent; item.emptyItem = marker.empty;
    item.node.ordered = marker.ordered; item.node.startNumber = marker.number;
    return marker.content;
  }
  parseLine(original: MarkdownBlockLine): void {
    let line: MarkdownBlockLine = this.match(original);
    if (line.offset === -1) { return; }
    if (this.continueLeaf(line)) { return; }
    // Every pass either consumes a container marker, creates a leaf, or closes a dangling list.
    while (true) {
      if (this.top().node.kind === 'list') {
        if (blockBlank(line, this.work)) {
          const items: MarkdownNode[] = this.top().node.children;
          const item: MarkdownNode = items[items.length - 1];
          item.children.push(markdownNode('blank', sourceStart(line), sourceEnd(line)));
          item.range.end = sourceEnd(line); this.touch(line); return;
        }
        const sibling: BlockListMarker | undefined = blockList(line, this.work);
        if (sibling === undefined || blockRule(line, this.work)) { this.close(); continue; }
      }
      if (blockBlank(line, this.work)) {
        // A marker-only first line is an empty item, not an intervening blank that loosens a list.
        if (this.top().node.kind === 'listItem' && this.top().emptyItem) { this.touch(line); return; }
        this.leaf(markdownNode('blank', sourceStart(line), sourceEnd(line)), line); return;
      }
      const tooDeep: boolean = this.frames.length >= MAX_BLOCK_DEPTH;
      const quote: MarkdownBlockLine | undefined = tooDeep ? undefined : blockQuote(line, this.work);
      if (quote !== undefined) {
        this.push(markdownNode('blockquote', sourceStart(line), sourceEnd(line))); line = quote; continue;
      }
      const fence: BlockFence | undefined = blockFence(line, this.work);
      if (fence !== undefined) {
        const language: string = decodeBlockValue(fence.info, this.work);
        // latex/tex 围栏旁路（U7-R4b）：产出 mathBlock 而非 codeBlock，闭合面同走
        // blockFenceClose（frame.fence 携带字形与缩进），未闭合即 mathBlock(closed=false)。
        if (MARKDOWN_LATEX_FENCE_ENABLED && markdownLatexFenceLanguage(language)) {
          const mathFrame: BlockFrame = this.push(markdownNode('mathBlock', sourceStart(line), sourceEnd(line)));
          mathFrame.fence = fence; mathFrame.node.closed = false;
          this.touch(line); return;
        }
        const frame: BlockFrame = this.push(markdownNode('codeBlock', sourceStart(line), sourceEnd(line)));
        frame.fence = fence; frame.node.language = language; frame.node.closed = false;
        this.touch(line); return;
      }
      const heading: BlockHeading | undefined = blockAtx(line, this.work);
      if (heading !== undefined) {
        const node: MarkdownNode = markdownNode('heading', sourceStart(line), sourceEnd(line)); node.level = heading.level;
        addSlice(node, line, heading.start, heading.end, this.work); headingId(node, this.work);
        this.leaf(node, line); return;
      }
      if (blockRule(line, this.work)) { this.leaf(markdownNode('thematicBreak', sourceStart(line), sourceEnd(line)), line); return; }
      const list: BlockListMarker | undefined = tooDeep ? undefined : blockList(line, this.work);
      if (list !== undefined) { line = this.openList(line, list); continue; }
      if (blockIndent(line, this.work).columns >= 4) {
        const frame: BlockFrame = this.push(markdownNode('codeBlock', sourceStart(line), sourceEnd(line)));
        frame.node.closed = true; frame.literals.push(blockLiteral(blockStrip(line, 4, this.work), this.work));
        this.touch(line); return;
      }
      const footnote: BlockHeading | undefined = tooDeep ? undefined : blockLabel(line, true, this.work);
      if (footnote !== undefined) {
        const frame: BlockFrame = this.push(markdownNode('footnoteDefinition', sourceStart(line), sourceEnd(line)));
        frame.indent = 4; frame.node.label = blockSlice(line.source, footnote.start, footnote.end, this.work);
        line = blockStrip(blockAfter(line, footnote.level, this.work), 1, this.work); continue;
      }
      if (blockToc(line, this.work)) { this.leaf(markdownNode('toc', sourceStart(line), sourceEnd(line)), line); return; }
      const html: number = blockHtml(line, this.work);
      if (html > 0) {
        const frame: BlockFrame = this.push(markdownNode('htmlBlock', sourceStart(line), sourceEnd(line)));
        frame.htmlType = html; frame.node.closed = html >= 6 || blockHtmlClose(line, html, this.work);
        frame.literals.push(blockLiteral(line, this.work)); this.touch(line);
        if (html < 6 && frame.node.closed) { this.close(); }
        return;
      }
      const math: BlockMath | undefined = blockMath(line, this.work);
      if (math !== undefined) {
        const frame: BlockFrame = this.push(markdownNode('mathBlock', sourceStart(line), sourceEnd(line)));
        frame.closer = math.closer; frame.node.closed = math.closed; this.touch(line);
        if (math.closed) {
          frame.literals.push(blockSlice(line.source, math.start, math.end, this.work));
          this.close();
        } else if (math.start < math.end) {
          // U7-R4c 第三形态：开栏行定界符后自带内容（同行无闭合）——首行余段并入围栏体，
          // 后续行照 continueLeaf 的 mathBlock 分支续收，闭合为整行定界符（blockMathClose）。
          frame.literals.push(blockLiteral(blockAfter(line, math.start, this.work), this.work));
        }
        return;
      }
      const frame: BlockFrame = this.push(markdownNode('paragraph', sourceStart(line), sourceEnd(line)));
      frame.lines.push(blockView(line)); this.touch(line); return;
    }
  }
  parse(source: string, offset: number): MarkdownNode[] {
    const lines: MarkdownBlockLine[] = blockLines(source, offset, this.work);
    for (let index: number = 0; index < lines.length; index++) { this.parseLine(lines[index]); }
    this.closeTo(1);
    return this.frames[0].node.children;
  }
}

export function parseMarkdownBlocks(source: string, offset: number, work: MarkdownSemanticWork): MarkdownNode[] {
  if (!Number.isInteger(offset) || offset < 0) { throw new Error('Markdown 源偏移必须为非负整数'); }
  return new MarkdownBlockParser(offset, work).parse(source, offset);
}
