/**
 * 块级词法与源行视图。视图不拼接去前缀全文；tab 的未消耗列只用于结构与代码，
 * 行内 parts 始终切自原文。所有扫描/子串物化分别累计，失败探测也不免计量。
 */
import { MarkdownNode, MarkdownSemanticWork, MarkdownTextSlice, markdownNode } from './MarkdownSemanticModel';

export class MarkdownBlockLine {
  source: string;
  start: number;
  end: number;
  bodyEnd: number;
  offset: number;
  position: number;
  column: number = 0;
  extra: number = 0;
  constructor(source: string, start: number, end: number, bodyEnd: number, offset: number) {
    this.source = source; this.start = start; this.end = end; this.bodyEnd = bodyEnd;
    this.offset = offset; this.position = start;
  }
}
export interface BlockIndent { position: number; columns: number; column: number; }
export interface BlockListMarker { character: string; ordered: boolean; number: number; indent: number; content: MarkdownBlockLine; empty: boolean; }
export interface BlockFence { character: string; length: number; indent: number; info: string; }
export interface BlockHeading { level: number; start: number; end: number; }
export interface BlockMath { closer: string; start: number; end: number; closed: boolean; }
export interface BlockCells { cells: MarkdownTextSlice[]; pipes: number; }
export interface BlockDefinition { node: MarkdownNode; consumed: number; }

export function blockChar(source: string, index: number, work: MarkdownSemanticWork): string {
  work.parsedUnits++;
  return source.charAt(index);
}
export function blockSlice(source: string, start: number, end: number, work: MarkdownSemanticWork): string {
  const length: number = Math.max(0, end - start);
  work.parsedUnits += length; work.materializedUnits += length;
  return source.substring(start, end);
}
export function blockJoin(values: string[], work: MarkdownSemanticWork): string {
  let length: number = 0;
  for (let index: number = 0; index < values.length; index++) { length += values[index].length; }
  work.parsedUnits += length; work.materializedUnits += length;
  return values.join('');
}
export function blockSpace(character: string): boolean { return character === ' ' || character === '\t'; }
export function blockLines(source: string, offset: number, work: MarkdownSemanticWork): MarkdownBlockLine[] {
  const lines: MarkdownBlockLine[] = [];
  let start: number = 0;
  let position: number = 0;
  while (position < source.length) {
    const character: string = blockChar(source, position, work);
    if (character !== '\r' && character !== '\n') { position++; continue; }
    const bodyEnd: number = position++;
    if (character === '\r' && blockChar(source, position, work) === '\n') { position++; }
    lines.push(new MarkdownBlockLine(source, start, position, bodyEnd, offset));
    start = position;
  }
  if (start < source.length) { lines.push(new MarkdownBlockLine(source, start, source.length, source.length, offset)); }
  return lines;
}
export function blockView(line: MarkdownBlockLine): MarkdownBlockLine {
  const result: MarkdownBlockLine = new MarkdownBlockLine(line.source, line.start, line.end, line.bodyEnd, line.offset);
  result.position = line.position; result.column = line.column; result.extra = line.extra;
  return result;
}
export function blockIndent(line: MarkdownBlockLine, work: MarkdownSemanticWork): BlockIndent {
  let position: number = line.position;
  let column: number = line.column;
  while (position < line.bodyEnd) {
    const character: string = blockChar(line.source, position, work);
    if (!blockSpace(character)) { break; }
    column += character === '\t' ? 4 - column % 4 : 1;
    position++;
  }
  return { position: position, columns: line.extra + column - line.column, column: column };
}
export function blockStrip(line: MarkdownBlockLine, columns: number, work: MarkdownSemanticWork): MarkdownBlockLine {
  const result: MarkdownBlockLine = blockView(line);
  const fromExtra: number = Math.min(result.extra, columns);
  result.extra -= fromExtra; columns -= fromExtra;
  while (columns > 0 && result.position < result.bodyEnd) {
    const character: string = blockChar(result.source, result.position, work);
    if (!blockSpace(character)) { break; }
    const width: number = character === '\t' ? 4 - result.column % 4 : 1;
    result.column += width; result.position++;
    if (width > columns) { result.extra = width - columns; columns = 0; } else { columns -= width; }
  }
  return result;
}
export function blockAfter(line: MarkdownBlockLine, position: number, work: MarkdownSemanticWork): MarkdownBlockLine {
  const result: MarkdownBlockLine = blockView(line);
  result.extra = 0;
  while (result.position < position) {
    const character: string = blockChar(result.source, result.position++, work);
    result.column += character === '\t' ? 4 - result.column % 4 : 1;
  }
  return result;
}
export function blockBlank(line: MarkdownBlockLine, work: MarkdownSemanticWork): boolean {
  return blockIndent(line, work).position === line.bodyEnd;
}
export function blockTrimEnd(line: MarkdownBlockLine, end: number, work: MarkdownSemanticWork): number {
  while (end > line.position && blockSpace(blockChar(line.source, end - 1, work))) { end--; }
  return end;
}
export function blockLiteral(line: MarkdownBlockLine, work: MarkdownSemanticWork): string {
  const prefix: string = ' '.repeat(line.extra);
  const text: string = blockSlice(line.source, line.position, line.bodyEnd, work);
  const ending: string = line.end > line.bodyEnd ? '\n' : '';
  return blockJoin([prefix, text, ending], work);
}
export function blockQuote(line: MarkdownBlockLine, work: MarkdownSemanticWork): MarkdownBlockLine | undefined {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3 || blockChar(line.source, indent.position, work) !== '>') { return undefined; }
  return blockStrip(blockAfter(line, indent.position + 1, work), 1, work);
}
export function blockList(line: MarkdownBlockLine, work: MarkdownSemanticWork): BlockListMarker | undefined {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3) { return undefined; }
  let position: number = indent.position;
  let character: string = blockChar(line.source, position, work);
  let ordered: boolean = false;
  let number: number = 1;
  if (character >= '0' && character <= '9') {
    ordered = true; number = 0;
    while (position < line.bodyEnd && position - indent.position < 9) {
      character = blockChar(line.source, position, work);
      if (character < '0' || character > '9') { break; }
      number = number * 10 + character.charCodeAt(0) - 48; position++;
    }
    character = blockChar(line.source, position, work);
    if (character !== '.' && character !== ')') { return undefined; }
  } else if (character !== '-' && character !== '+' && character !== '*') { return undefined; }
  position++;
  if (position < line.bodyEnd && !blockSpace(blockChar(line.source, position, work))) { return undefined; }
  const afterMarker: MarkdownBlockLine = blockAfter(line, position, work);
  const spaces: BlockIndent = blockIndent(afterMarker, work);
  const empty: boolean = spaces.position === line.bodyEnd;
  const padding: number = empty || spaces.columns > 4 ? 1 : spaces.columns;
  const content: MarkdownBlockLine = empty ? blockAfter(afterMarker, line.bodyEnd, work) : blockStrip(afterMarker, padding, work);
  return { character: character, ordered: ordered, number: number,
    indent: indent.columns + position - indent.position + padding, content: content, empty: empty };
}
export function blockRule(line: MarkdownBlockLine, work: MarkdownSemanticWork): boolean {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3) { return false; }
  const marker: string = blockChar(line.source, indent.position, work);
  if (marker !== '*' && marker !== '-' && marker !== '_') { return false; }
  let count: number = 0;
  for (let index: number = indent.position; index < line.bodyEnd; index++) {
    const character: string = blockChar(line.source, index, work);
    if (character === marker) { count++; } else if (!blockSpace(character)) { return false; }
  }
  return count >= 3;
}
export function blockSetext(line: MarkdownBlockLine, work: MarkdownSemanticWork): number {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3) { return 0; }
  const marker: string = blockChar(line.source, indent.position, work);
  if (marker !== '=' && marker !== '-') { return 0; }
  let position: number = indent.position;
  while (position < line.bodyEnd && blockChar(line.source, position, work) === marker) { position++; }
  while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
  return position === line.bodyEnd ? (marker === '=' ? 1 : 2) : 0;
}
export function blockAtx(line: MarkdownBlockLine, work: MarkdownSemanticWork): BlockHeading | undefined {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3) { return undefined; }
  let position: number = indent.position;
  while (position < line.bodyEnd && position - indent.position < 7 && blockChar(line.source, position, work) === '#') { position++; }
  const level: number = position - indent.position;
  if (level < 1 || level > 6 || (position < line.bodyEnd && !blockSpace(blockChar(line.source, position, work)))) { return undefined; }
  const markerEnd: number = position;
  while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
  let end: number = blockTrimEnd(line, line.bodyEnd, work);
  let closer: number = end;
  while (closer > markerEnd && blockChar(line.source, closer - 1, work) === '#') { closer--; }
  if (closer < end && closer > markerEnd && blockSpace(blockChar(line.source, closer - 1, work))) {
    end = Math.max(position, blockTrimEnd(line, closer, work));
  }
  return { level: level, start: position, end: end };
}
export function blockFence(line: MarkdownBlockLine, work: MarkdownSemanticWork): BlockFence | undefined {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3) { return undefined; }
  const marker: string = blockChar(line.source, indent.position, work);
  if (marker !== '`' && marker !== '~') { return undefined; }
  let position: number = indent.position;
  while (position < line.bodyEnd && blockChar(line.source, position, work) === marker) { position++; }
  const length: number = position - indent.position;
  if (length < 3) { return undefined; }
  const infoStart: number = position;
  if (marker === '`') {
    for (let index: number = position; index < line.bodyEnd; index++) {
      if (blockChar(line.source, index, work) === '`') { return undefined; }
    }
  }
  position = infoStart;
  while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
  let end: number = position;
  while (end < line.bodyEnd && !blockSpace(blockChar(line.source, end, work))) { end++; }
  return { character: marker, length: length, indent: indent.columns, info: blockSlice(line.source, position, end, work) };
}
export function blockFenceClose(line: MarkdownBlockLine, fence: BlockFence, work: MarkdownSemanticWork): boolean {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3) { return false; }
  let position: number = indent.position;
  while (position < line.bodyEnd && blockChar(line.source, position, work) === fence.character) { position++; }
  if (position - indent.position < fence.length) { return false; }
  while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
  return position === line.bodyEnd;
}
export function blockToc(line: MarkdownBlockLine, work: MarkdownSemanticWork): boolean {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3 || blockTrimEnd(line, line.bodyEnd, work) - indent.position !== 5) { return false; }
  return blockSlice(line.source, indent.position, indent.position + 5, work).toLowerCase() === '[toc]';
}
export function blockMath(line: MarkdownBlockLine, work: MarkdownSemanticWork): BlockMath | undefined {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3) { return undefined; }
  const opener: string = blockSlice(line.source, indent.position, Math.min(line.bodyEnd, indent.position + 2), work);
  if (opener !== '$$' && opener !== '\\[') { return undefined; }
  const closer: string = opener === '$$' ? '$$' : '\\]';
  const end: number = blockTrimEnd(line, line.bodyEnd, work);
  if (end === indent.position + 2) { return { closer: closer, start: end, end: end, closed: false }; }
  // 第三形态（U7-R4c）：开栏行定界符后带内容且同行无闭合定界符 → 跨行块级公式开栏；
  // start 指向开栏行余段起点（首行内容入公式体由调用方按 start<end 判定），end 取去尾空白位
  //（纯空白尾不算内容）；闭合行为整行定界符（blockMathClose，与既有开栏同判）。
  if (end < indent.position + 4 || blockSlice(line.source, end - 2, end, work) !== closer) {
    return { closer: closer, start: indent.position + 2, end: end, closed: false };
  }
  let escapes: number = 0;
  for (let index: number = end - 3; index >= indent.position + 2 && blockChar(line.source, index, work) === '\\'; index--) { escapes++; }
  if (escapes % 2 !== 0) { return undefined; }
  return { closer: closer, start: indent.position + 2, end: end - 2, closed: true };
}
export function blockMathClose(line: MarkdownBlockLine, closer: string, work: MarkdownSemanticWork): boolean {
  const indent: BlockIndent = blockIndent(line, work);
  return indent.columns <= 3 && blockTrimEnd(line, line.bodyEnd, work) - indent.position === 2 &&
    blockSlice(line.source, indent.position, indent.position + 2, work) === closer;
}

const HTML_BLOCK_TAGS: string = '|address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul|';
function asciiLetter(character: string): boolean { return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z'); }
function nameCharacter(character: string): boolean { return asciiLetter(character) || (character >= '0' && character <= '9') || character === '-'; }
function htmlComplete(line: MarkdownBlockLine, position: number, closing: boolean, work: MarkdownSemanticWork): boolean {
  while (position < line.bodyEnd) {
    const beforeSpace: number = position;
    while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
    let character: string = blockChar(line.source, position, work);
    if (character === '/' && !closing) { position++; character = blockChar(line.source, position, work); }
    if (character === '>') {
      position++;
      while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
      return position === line.bodyEnd;
    }
    if (closing || position === beforeSpace || !(asciiLetter(character) || character === '_' || character === ':')) { return false; }
    position++;
    while (position < line.bodyEnd) {
      character = blockChar(line.source, position, work);
      if (!(nameCharacter(character) || character === '_' || character === ':' || character === '.')) { break; }
      position++;
    }
    const afterName: number = position;
    while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
    if (blockChar(line.source, position, work) !== '=') { position = afterName; continue; }
    position++;
    while (position < line.bodyEnd && blockSpace(blockChar(line.source, position, work))) { position++; }
    character = blockChar(line.source, position, work);
    if (character === '"' || character === "'") {
      const quote: string = character; position++;
      while (position < line.bodyEnd && blockChar(line.source, position, work) !== quote) { position++; }
      if (position === line.bodyEnd) { return false; }
      position++;
    } else {
      const valueStart: number = position;
      while (position < line.bodyEnd) {
        character = blockChar(line.source, position, work);
        if (blockSpace(character) || character === '>') { break; }
        if (character === '"' || character === "'" || character === '=' || character === '<' || character === '`') { return false; }
        position++;
      }
      if (position === valueStart) { return false; }
    }
  }
  return false;
}
export function blockHtml(line: MarkdownBlockLine, work: MarkdownSemanticWork): number {
  const indent: BlockIndent = blockIndent(line, work);
  if (indent.columns > 3 || blockChar(line.source, indent.position, work) !== '<') { return 0; }
  const prefix: string = blockSlice(line.source, indent.position, Math.min(line.bodyEnd, indent.position + 9), work);
  if (prefix.startsWith('<!--')) { return 2; }
  if (prefix.startsWith('<?')) { return 3; }
  if (prefix.startsWith('<![CDATA[')) { return 5; }
  if (prefix.startsWith('<!') && asciiLetter(prefix.charAt(2))) { return 4; }
  const closing: boolean = blockChar(line.source, indent.position + 1, work) === '/';
  const start: number = indent.position + (closing ? 2 : 1);
  if (!asciiLetter(blockChar(line.source, start, work))) { return 0; }
  let position: number = start + 1;
  while (position < line.bodyEnd && nameCharacter(blockChar(line.source, position, work))) { position++; }
  const tag: string = blockSlice(line.source, start, position, work).toLowerCase();
  const next: string = position === line.bodyEnd ? '' : blockChar(line.source, position, work);
  const ordinaryEnd: boolean = next === '' || next === '>' || blockSpace(next);
  if (!closing && ordinaryEnd && (tag === 'pre' || tag === 'script' || tag === 'style' || tag === 'textarea')) { return 1; }
  if ((ordinaryEnd || (next === '/' && blockChar(line.source, position + 1, work) === '>')) && HTML_BLOCK_TAGS.indexOf('|' + tag + '|') >= 0) { return 6; }
  return htmlComplete(line, position, closing, work) ? 7 : 0;
}
export function blockHtmlClose(line: MarkdownBlockLine, type: number, work: MarkdownSemanticWork): boolean {
  if (type >= 6) { return blockBlank(line, work); }
  // Fixed delimiters / fixed alternatives have linear matching cost, never a nested wildcard regex.
  const text: string = blockSlice(line.source, line.position, line.bodyEnd, work);
  work.parsedUnits += text.length;
  if (type === 1) {
    work.materializedUnits += text.length; work.parsedUnits += text.length;
    return /<\/(pre|script|style|textarea)>/i.test(text);
  }
  return text.indexOf(type === 2 ? '-->' : type === 3 ? '?>' : type === 4 ? '>' : ']]>') >= 0;
}

export function blockCells(line: MarkdownBlockLine, work: MarkdownSemanticWork): BlockCells {
  const runs: number[] = [];
  const lengths: number[] = [];
  for (let index: number = line.position; index < line.bodyEnd;) {
    const character: string = blockChar(line.source, index, work);
    // Backslashes are literal inside code; even an escaped run can close an earlier opener.
    if (character !== '`') { index++; continue; }
    const start: number = index++;
    while (index < line.bodyEnd && blockChar(line.source, index, work) === '`') { index++; }
    runs.push(start); lengths.push(index - start);
  }
  const next: number[] = new Array<number>(runs.length).fill(-1);
  const afterEscape: number[] = new Array<number>(runs.length).fill(-1);
  const last: Map<number, number> = new Map<number, number>();
  for (let index: number = runs.length - 1; index >= 0; index--) {
    const match: number | undefined = last.get(lengths[index]);
    const shortened: number | undefined = last.get(lengths[index] - 1);
    if (match !== undefined) { next[index] = match; }
    if (shortened !== undefined) { afterEscape[index] = shortened; }
    last.set(lengths[index], index);
  }
  const pipes: number[] = [];
  let run: number = 0;
  for (let index: number = line.position; index < line.bodyEnd;) {
    const character: string = blockChar(line.source, index, work);
    while (run < runs.length && runs[run] + lengths[run] <= index) { run++; }
    if (character === '\\') { index += Math.min(2, line.bodyEnd - index); continue; }
    if (run < runs.length && (index === runs[run] || index === runs[run] + 1)) {
      // An escape removes only the first tick; the remaining run can still open a code span.
      const close: number = index === runs[run] ? next[run] : afterEscape[run];
      if (close >= 0) { index = runs[close] + lengths[close]; run = close + 1; }
      else { index = runs[run] + lengths[run]; run++; }
      continue;
    }
    if (character === '|') { pipes.push(index); }
    index++;
  }
  const left: number = blockIndent(line, work).position;
  const right: number = blockTrimEnd(line, line.bodyEnd, work);
  const boundaries: number[] = [line.position - 1];
  for (let index: number = 0; index < pipes.length; index++) { boundaries.push(pipes[index]); }
  boundaries.push(line.bodyEnd);
  let first: number = 0;
  let count: number = boundaries.length - 1;
  if (pipes.length > 0 && pipes[0] === left) { first++; }
  if (pipes.length > 0 && pipes[pipes.length - 1] === right - 1) { count--; }
  const cells: MarkdownTextSlice[] = [];
  for (let index: number = first; index < count; index++) {
    let start: number = boundaries[index] + 1;
    let end: number = boundaries[index + 1];
    while (start < end && blockSpace(blockChar(line.source, start, work))) { start++; }
    while (end > start && blockSpace(blockChar(line.source, end - 1, work))) { end--; }
    cells.push({ text: blockSlice(line.source, start, end, work), start: line.offset + start });
  }
  return { cells: cells, pipes: pipes.length };
}
export function blockAlignments(cells: MarkdownTextSlice[], work: MarkdownSemanticWork): string[] | undefined {
  if (cells.length === 0) { return undefined; }
  const result: string[] = [];
  for (let index: number = 0; index < cells.length; index++) {
    const text: string = cells[index].text;
    let position: number = 0;
    const left: boolean = blockChar(text, 0, work) === ':';
    if (left) { position++; }
    const start: number = position;
    while (position < text.length && blockChar(text, position, work) === '-') { position++; }
    if (position - start < 3) { return undefined; }
    const right: boolean = blockChar(text, position, work) === ':';
    if (right) { position++; }
    if (position !== text.length) { return undefined; }
    result.push(left && right ? 'center' : right ? 'right' : left ? 'left' : '');
  }
  return result;
}

/** A bounded label scan is shared by footnotes and ordinary reference definitions. */
export function blockLabel(line: MarkdownBlockLine, footnote: boolean, work: MarkdownSemanticWork): BlockHeading | undefined {
  const indent: BlockIndent = blockIndent(line, work);
  const start: number = indent.position + (footnote ? 2 : 1);
  if (indent.columns > 3 || blockChar(line.source, indent.position, work) !== '[' ||
    (footnote && blockChar(line.source, indent.position + 1, work) !== '^')) { return undefined; }
  let position: number = start;
  while (position < line.bodyEnd && position - start <= 999) {
    const character: string = blockChar(line.source, position, work);
    if (character === '\\') { position += 2; continue; }
    if (character === '[') { return undefined; }
    if (character === ']') {
      if (position === start || blockChar(line.source, position + 1, work) !== ':') { return undefined; }
      return { level: position + 2, start: start, end: position };
    }
    position++;
  }
  return undefined;
}

class DefinitionCursor {
  lines: MarkdownBlockLine[];
  row: number;
  position: number;
  work: MarkdownSemanticWork;
  constructor(lines: MarkdownBlockLine[], row: number, work: MarkdownSemanticWork) {
    this.lines = lines; this.row = row; this.position = blockIndent(lines[row], work).position; this.work = work;
  }
  peek(): string {
    if (this.row >= this.lines.length) { return ''; }
    const line: MarkdownBlockLine = this.lines[this.row];
    return this.position < line.bodyEnd ? blockChar(line.source, this.position, this.work) : '\n';
  }
  step(): void {
    if (this.row >= this.lines.length) { return; }
    if (this.position < this.lines[this.row].bodyEnd) { this.position++; }
    else { this.row++; if (this.row < this.lines.length) { this.position = this.lines[this.row].position; } }
  }
  spaces(newlines: number): void {
    while (this.row < this.lines.length) {
      const character: string = this.peek();
      if (blockSpace(character)) { this.step(); }
      else if (character === '\n' && newlines > 0) { this.step(); newlines--; }
      else { break; }
    }
  }
}
export function blockDefinition(lines: MarkdownBlockLine[], first: number, work: MarkdownSemanticWork): BlockDefinition | undefined {
  const initial: MarkdownBlockLine = lines[first];
  if (blockIndent(initial, work).columns > 3) { return undefined; }
  const cursor: DefinitionCursor = new DefinitionCursor(lines, first, work);
  if (cursor.peek() !== '[') { return undefined; }
  cursor.step();
  const label: string[] = [];
  while (cursor.row < lines.length && label.length <= 999) {
    const character: string = cursor.peek();
    if (character === '[') { return undefined; }
    if (character === ']') { break; }
    label.push(character); cursor.step();
    if (character === '\\' && cursor.peek() !== '\n') { label.push(cursor.peek()); cursor.step(); }
  }
  if (label.length > 999 || cursor.peek() !== ']') { return undefined; }
  cursor.step();
  if (cursor.peek() !== ':') { return undefined; }
  cursor.step(); cursor.spaces(1);
  const destination: string[] = [];
  if (cursor.peek() === '<') {
    cursor.step();
    while (cursor.row < lines.length && cursor.peek() !== '>') {
      const character: string = cursor.peek();
      if (character === '\n' || character === '<') { return undefined; }
      destination.push(character); cursor.step();
      if (character === '\\' && cursor.peek() !== '\n') { destination.push(cursor.peek()); cursor.step(); }
    }
    if (cursor.peek() !== '>') { return undefined; }
    cursor.step();
  } else {
    let balance: number = 0;
    while (cursor.row < lines.length) {
      const character: string = cursor.peek();
      if (character === '\n' || character.charCodeAt(0) <= 32) { break; }
      if (character === '(') { balance++; }
      if (character === ')') { if (balance === 0) { break; } balance--; }
      destination.push(character); cursor.step();
      if (character === '\\' && cursor.peek() !== '\n') { destination.push(cursor.peek()); cursor.step(); }
    }
    if (destination.length === 0 || balance !== 0) { return undefined; }
  }
  const destinationRow: number = cursor.row;
  const separated: boolean = blockSpace(cursor.peek()) || cursor.peek() === '\n';
  cursor.spaces(0);
  const destinationComplete: boolean = cursor.peek() === '\n' || cursor.peek() === '';
  cursor.spaces(1);
  const opener: string = cursor.peek();
  const title: string[] = [];
  let consumed: number = destinationRow - first + 1;
  if (separated && (opener === '"' || opener === "'" || opener === '(')) {
    const titleRow: number = cursor.row;
    const closer: string = opener === '(' ? ')' : opener;
    cursor.step();
    let valid: boolean = false;
    while (cursor.row < lines.length) {
      const character: string = cursor.peek();
      if (character === closer) { cursor.step(); cursor.spaces(0); valid = cursor.peek() === '\n' || cursor.peek() === ''; break; }
      if (character === '\n' && cursor.row + 1 < lines.length && blockBlank(lines[cursor.row + 1], work)) { break; }
      if (character === '(' && opener === '(') { break; }
      title.push(character); cursor.step();
      if (character === '\\' && cursor.peek() !== '\n') { title.push(cursor.peek()); cursor.step(); }
    }
    if (valid) { consumed = cursor.row - first + 1; }
    else if (titleRow === destinationRow || !destinationComplete) { return undefined; }
    else { title.length = 0; }
  } else if (!destinationComplete) { return undefined; }
  const labelText: string = blockJoin(label, work);
  work.parsedUnits += labelText.length;
  if (labelText.trim().length === 0) { return undefined; }
  const node: MarkdownNode = markdownNode('referenceDefinition', initial.offset + initial.position,
    lines[first + consumed - 1].offset + lines[first + consumed - 1].end);
  node.label = labelText; node.destination = blockJoin(destination, work); node.title = blockJoin(title, work);
  return { node: node, consumed: consumed };
}
