/**
 * CommonMark 0.31.2 行内定界符/括号栈；项目扩展见设计-流式Markdown语义解析。
 * 项目扩展定界：==高亮==（恰两枚成对；偏好开关已退役、==高亮== 恒开，恒用开态文本截断类
 * INLINE_TEXT_STOP_MARK）。不执行 HTML/URL。parts 的 UTF-16 单元逐一
 * 映射原文，语义文字不反写源串。最大语义深度 64；失败前瞻共享 128N+4096 扫描预算，越限
 * 保留剩余源码。inlineUnits 计字符读取/索引/栈查找/源映射访问；materializedUnits 计实际
 * substring/join/解码输出；实体解码输入另计扫描量，不将失败重扫伪称增量。
 */
import { MarkdownInlineContext, MarkdownNode, MarkdownNodeKind, MarkdownReference, MarkdownTextSlice,
  markdownNode, normalizeMarkdownLabel } from './MarkdownSemanticModel';
import { decodeMarkdownEntities } from './MarkdownEntities';

const INLINE_DEPTH: number = 64;
const ASCII_ESCAPE: RegExp = /^[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]$/;
const INLINE_SPACE: RegExp = /^[\p{Zs}\t\n\f\r]$/u;
const INLINE_PUNCT: RegExp = /^[\p{P}\p{S}]$/u;
const EMAIL_LOCAL: RegExp = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]$/;
const DOMAIN_CHAR: RegExp = /^[a-zA-Z0-9.-]$/;
// 行内文本 run 的截断类（U7）：恒含 `=`（`=` run 须独立成 token 才能与后续 `==` 配对）。
// ★ 2026-11-12 自检轮：「行内高亮」偏好退役后关态基类（不含 `=`）已无消费方，随开关一并删。
const INLINE_TEXT_STOP_MARK: RegExp = /[`$\\\r\n &<!\[\]*_~^=]/;

class InlineToken {
  kind: MarkdownNodeKind = 'text';
  start: number;
  end: number;
  innerStart: number;
  innerEnd: number;
  value: string | undefined = undefined;
  destination: string = '';
  title: string = '';
  label: string = '';
  number: number = 1;
  closed: boolean = true;
  escapedSpace: boolean = false;
  height: number = 0;
  children: InlineToken[] = [];
  previous: InlineToken | undefined = undefined;
  next: InlineToken | undefined = undefined;
  constructor(start: number, end: number) {
    this.start = start; this.end = end; this.innerStart = start; this.innerEnd = end;
  }
}

class InlineDelimiter {
  token: InlineToken;
  symbol: string;
  length: number;
  original: number;
  opens: boolean;
  closes: boolean;
  sequence: number;
  previous: InlineDelimiter | undefined = undefined;
  next: InlineDelimiter | undefined = undefined;
  constructor(token: InlineToken, symbol: string, length: number, opens: boolean,
    closes: boolean, sequence: number) {
    this.token = token; this.symbol = symbol; this.length = length; this.original = length;
    this.opens = opens; this.closes = closes; this.sequence = sequence;
  }
}

interface InlineBracket {
  token: InlineToken;
  bottom: InlineDelimiter;
  image: boolean;
  active: boolean;
}
interface InlineTarget { end: number; destination: string; title: string; label: string; }
interface InlineBare { end: number; next: number; destination: string; }

function inlineWhite(character: string): boolean {
  return character.length === 0 || INLINE_SPACE.test(character);
}
function inlinePunct(character: string): boolean { return INLINE_PUNCT.test(character); }
function inlineAsciiLetter(character: string): boolean { return /^[a-zA-Z]$/.test(character); }

class MarkdownInlineParser {
  private text: string;
  private positions: number[] = [];
  private spaces: number[] = [0];
  private backticks: Map<number, number[]> = new Map<number, number[]>();
  private context: MarkdownInlineContext;
  private budget: number;
  private root: InlineToken = new InlineToken(0, 0);
  private tail: InlineToken = this.root;
  private delimiters: InlineDelimiter = new InlineDelimiter(this.root, '', 0, false, false, 0);
  private delimiterTail: InlineDelimiter = this.delimiters;
  private sequence: number = 0;
  private brackets: InlineBracket[] = [];
  // ==高亮== 恒开（U7）：偏好键已退役、行为固化为不可关闭——`=` 恒入定界集与文本截断类。
  // ★ 2026-11-12 自检轮：原「开关旗标 + 两态截断类三目」随退役一并删除（旗标恒 true、三目
  // 假支永不可达 = 死形态），恒开由 `textStop` 单值直接承接，语义逐字等价。
  private textStop: RegExp = INLINE_TEXT_STOP_MARK;

  constructor(parts: MarkdownTextSlice[], context: MarkdownInlineContext) {
    this.context = context;
    const strings: string[] = [];
    for (let partIndex: number = 0; partIndex < parts.length; partIndex++) {
      const part: MarkdownTextSlice = parts[partIndex];
      strings.push(part.text);
      for (let index: number = 0; index < part.text.length; index++) {
        this.positions.push(part.start + index); context.work.inlineUnits++;
      }
    }
    this.text = strings.join(''); context.work.materializedUnits += this.text.length;
    this.budget = this.text.length * 128 + 4096;
    let escaped: boolean = false;
    for (let index: number = 0; index < this.text.length; index++) {
      const character: string = this.read(index);
      this.spaces.push(this.spaces[index] +
        (inlineWhite(character) && !(escaped && character === ' ') ? 1 : 0));
      escaped = character === '\\' && !escaped;
    }
    for (let index: number = 0; index < this.text.length;) {
      if (this.read(index) !== '`') { index++; continue; }
      const start: number = index++;
      while (index < this.text.length && this.read(index) === '`') { index++; }
      const length: number = index - start;
      let runs: number[] | undefined = this.backticks.get(length);
      if (runs === undefined) { runs = []; this.backticks.set(length, runs); }
      runs.push(start);
    }
  }

  private read(index: number): string {
    this.context.work.inlineUnits++; this.budget--;
    return index < 0 || index >= this.text.length ? '' : this.text.charAt(index);
  }
  private raw(start: number, end: number): string {
    this.context.work.materializedUnits += Math.max(0, end - start);
    return this.text.substring(start, end);
  }
  private point(index: number, before: boolean = false): string {
    const character: string = this.read(index);
    const code: number = character.charCodeAt(0);
    if (before && code >= 0xdc00 && code <= 0xdfff && index > 0) {
      return this.read(index - 1) + character;
    }
    if (!before && code >= 0xd800 && code <= 0xdbff && index + 1 < this.text.length) {
      return character + this.read(index + 1);
    }
    return character;
  }
  private matches(index: number, value: string, fold: boolean = false): boolean {
    for (let offset: number = 0; offset < value.length; offset++) {
      const character: string = this.read(index + offset);
      if ((fold ? character.toLowerCase() : character) !== value.charAt(offset)) { return false; }
    }
    return true;
  }
  private decoded(start: number, end: number): string {
    const chunks: string[] = [];
    let run: number = start;
    for (let index: number = start; index < end; index++) {
      if (this.read(index) !== '\\' || !ASCII_ESCAPE.test(this.read(index + 1))) { continue; }
      // 转义后的 & 不能二次当实体起点，实体的输出也不能再次作为反斜线转义输入。
      const value: string = decodeMarkdownEntities(this.raw(run, index));
      this.context.work.inlineUnits += index - run;
      this.context.work.materializedUnits += value.length;
      chunks.push(value); chunks.push(this.read(++index)); run = index + 1;
    }
    const value: string = decodeMarkdownEntities(this.raw(run, end));
    this.context.work.inlineUnits += end - run;
    this.context.work.materializedUnits += value.length;
    chunks.push(value);
    const result: string = chunks.join('');
    this.context.work.materializedUnits += result.length; return result;
  }
  private append(token: InlineToken): void {
    token.previous = this.tail; this.tail.next = token; this.tail = token;
  }
  private removeToken(token: InlineToken): void {
    if (token.previous !== undefined) { token.previous.next = token.next; }
    if (token.next !== undefined) { token.next.previous = token.previous; }
    else { this.tail = token.previous === undefined ? this.root : token.previous; }
  }
  private removeDelimiter(delimiter: InlineDelimiter): void {
    if (delimiter.previous !== undefined) { delimiter.previous.next = delimiter.next; }
    if (delimiter.next !== undefined) { delimiter.next.previous = delimiter.previous; }
    else { this.delimiterTail = delimiter.previous === undefined ? this.delimiters : delimiter.previous; }
  }

  parse(): MarkdownNode[] {
    let index: number = 0;
    while (index < this.text.length && this.budget > 0) {
      const character: string = this.read(index);
      let token: InlineToken | undefined = undefined;
      if (character === '`') { token = this.code(index); }
      else if (character === '$' || (character === '\\' &&
        (this.read(index + 1) === '(' || this.read(index + 1) === '['))) { token = this.math(index); }
      if (token !== undefined) { this.append(token); index = token.end; continue; }
      if (character === '\\') {
        const next: string = this.read(index + 1);
        if (next === '\r' || next === '\n') { token = this.lineBreak(index, index + 1, true); }
        else if (ASCII_ESCAPE.test(next) || next === ' ') {
          token = new InlineToken(index, index + 2);
          token.escapedSpace = next === ' ';
          token.value = next === ' ' ? (index + 2 === this.text.length ? '\\' : '\\ ') : next;
        }
      } else if (character === '\r' || character === '\n') {
        token = this.lineBreak(index, index, false);
      } else if (character === ' ') {
        let end: number = index + 1;
        while (end < this.text.length && this.read(end) === ' ') { end++; }
        if (this.read(end) === '\r' || this.read(end) === '\n') {
          token = this.lineBreak(index, end, end - index >= 2);
        } else { token = new InlineToken(index, end); if (end === this.text.length) { token.value = ''; } }
      } else if (character === '&') { token = this.entity(index); }
      else if (character === '<') { token = this.angle(index); }
      else if (character === '[' || (character === '!' && this.read(index + 1) === '[')) {
        if (this.brackets.length >= INLINE_DEPTH) { break; }
        const image: boolean = character === '!';
        token = !image ? this.footnote(index) : undefined;
        if (token === undefined) {
          token = new InlineToken(index, index + (image ? 2 : 1));
          this.brackets.push({ token: token, bottom: this.delimiterTail, image: image, active: true });
        }
      } else if (character === ']') {
        const end: number = this.closeBracket(index);
        if (end > index) { index = end; continue; }
      } else if (character === '*' || character === '_' || character === '~' || character === '^' ||
        character === '=') {
        let end: number = index + 1;
        while (end < this.text.length && this.read(end) === character) { end++; }
        token = new InlineToken(index, end);
        const before: string = this.point(index - 1, true);
        const after: string = this.point(end);
        const left: boolean = !inlineWhite(after) &&
          (!inlinePunct(after) || inlineWhite(before) || inlinePunct(before));
        const right: boolean = !inlineWhite(before) &&
          (!inlinePunct(before) || inlineWhite(after) || inlinePunct(after));
        // `^` 限 run 恰 1、`=` 限 run 恰 2（==高亮==）——其余长度是文字不是定界符。
        if ((character !== '^' || end - index === 1) && (character !== '=' || end - index === 2)) {
          const delimiter: InlineDelimiter = new InlineDelimiter(token, character, end - index,
            character === '_' ? left && (!right || inlinePunct(before)) : left,
            character === '_' ? right && (!left || inlinePunct(after)) : right, ++this.sequence);
          delimiter.previous = this.delimiterTail; this.delimiterTail.next = delimiter;
          this.delimiterTail = delimiter;
        }
      }
      if (token === undefined) {
        let end: number = index + 1;
        while (end < this.text.length && !this.textStop.test(this.read(end))) { end++; }
        token = new InlineToken(index, end);
      }
      this.append(token); index = token.end;
    }
    if (index < this.text.length) { this.append(new InlineToken(index, this.text.length)); }
    this.processDelimiters(this.delimiters);
    const tokens: InlineToken[] = [];
    let current: InlineToken | undefined = this.root.next;
    while (current !== undefined) { tokens.push(current); current = current.next; }
    return this.materialize(tokens, false, false);
  }

  private lineBreak(start: number, newline: number, hard: boolean): InlineToken {
    let end: number = newline + (this.read(newline) === '\r' && this.read(newline + 1) === '\n' ? 2 : 1);
    while (this.read(end) === ' ' || this.read(end) === '\t') { end++; }
    const token: InlineToken = new InlineToken(start, end);
    token.kind = hard ? 'hardBreak' : 'softBreak'; return token;
  }
  private entity(start: number): InlineToken | undefined {
    let end: number = start + 1;
    while (end < this.text.length && end - start <= 34 && /[a-zA-Z0-9#]/.test(this.read(end))) { end++; }
    if (this.read(end) !== ';') { return undefined; }
    const raw: string = this.raw(start, end + 1);
    this.context.work.inlineUnits += raw.length;
    const value: string = decodeMarkdownEntities(raw);
    this.context.work.materializedUnits += value.length;
    if (value === raw) { return undefined; }
    const token: InlineToken = new InlineToken(start, end + 1); token.value = value; return token;
  }
  private code(start: number): InlineToken | undefined {
    let end: number = start + 1;
    while (this.read(end) === '`') { end++; }
    const length: number = end - start;
    const runs: number[] | undefined = this.backticks.get(length);
    if (runs === undefined) { return new InlineToken(start, end); }
    let low: number = 0; let high: number = runs.length;
    while (low < high) {
      this.context.work.inlineUnits++;
      const middle: number = Math.floor((low + high) / 2);
      if (runs[middle] < end) { low = middle + 1; } else { high = middle; }
    }
    // 未闭合的整个 run 是文字，不得从第二枚反引号重试较短闭合。
    if (low >= runs.length) { return new InlineToken(start, end); }
    const close: number = runs[low];
    const token: InlineToken = new InlineToken(start, close + length);
    token.kind = 'code'; token.innerStart = end; token.innerEnd = close;
    let value: string = this.raw(end, close);
    this.context.work.inlineUnits += value.length * 2;
    value = value.replace(/\r\n|[\r\n]/g, ' ');
    this.context.work.materializedUnits += value.length;
    if (value.startsWith(' ') && value.endsWith(' ') && /[^ ]/.test(value)) {
      value = value.substring(1, value.length - 1); this.context.work.materializedUnits += value.length;
    }
    token.value = value; return token;
  }
  private math(start: number): InlineToken | undefined {
    const slash: boolean = this.read(start) === '\\';
    const size: number = slash || this.read(start + 1) === '$' ? 2 : 1;
    if (!slash && size === 1 && inlineWhite(this.point(start + 1))) { return undefined; }
    const closing: string = slash ? (this.read(start + 1) === '(' ? '\\)' : '\\]') : (size === 2 ? '$$' : '$');
    let index: number = start + size;
    let closed: boolean = false;
    while (index < this.text.length && this.budget > 0) {
      if (this.matches(index, closing) && (slash || size === 2 ||
        (!inlineWhite(this.point(index - 1, true)) && !/^[0-9]$/.test(this.read(index + 1)) &&
          this.read(index - 1) !== '$' && this.read(index + 1) !== '$'))) { closed = true; break; }
      if (this.read(index) === '\\' && index + 1 < this.text.length) { index += 2; }
      else { index++; }
    }
    if (!closed && !slash && size === 1 && /^[0-9]$/.test(this.read(start + 1))) { return undefined; }
    if (!closed) { index = this.text.length; }
    const token: InlineToken = new InlineToken(start, index + (closed ? size : 0));
    token.kind = 'math'; token.innerStart = start + size; token.innerEnd = index;
    token.closed = closed; token.value = this.raw(token.innerStart, index); return token;
  }

  private footnote(start: number): InlineToken | undefined {
    if (this.read(start + 1) !== '^') { return undefined; }
    const end: number = this.labelEnd(start + 2);
    if (end < 0) { return undefined; }
    const label: string = this.label(start + 2, end);
    const number: number | undefined = this.context.footnotes.get(label);
    if (number === undefined) { return undefined; }
    const token: InlineToken = new InlineToken(start, end + 1);
    token.kind = 'footnoteReference'; token.label = label; token.number = number; return token;
  }
  private label(start: number, end: number): string {
    const raw: string = this.raw(start, end);
    this.context.work.inlineUnits += raw.length * 3;
    const label: string = normalizeMarkdownLabel(raw);
    this.context.work.materializedUnits += label.length; return label;
  }
  private labelEnd(start: number): number {
    let index: number = start;
    while (index < this.text.length && index - start <= 999 && this.budget > 0) {
      const character: string = this.read(index);
      if (character === ']') { return index; }
      if (character === '[') { return -1; }
      if (character === '\\' && ASCII_ESCAPE.test(this.read(index + 1))) { index++; }
      index++;
    }
    return -1;
  }
  private skipSpace(start: number): number {
    let index: number = start; let newlines: number = 0;
    while (index < this.text.length && this.budget > 0) {
      const character: string = this.read(index);
      if (character === '\r' || character === '\n') {
        if (++newlines > 1) { return -1; }
        if (character === '\r' && this.read(index + 1) === '\n') { index++; }
      } else if (character !== ' ' && character !== '\t') { break; }
      index++;
    }
    return index;
  }
  private target(start: number): InlineTarget | undefined {
    let index: number = this.skipSpace(start + 1);
    if (index < 0) { return undefined; }
    let destinationStart: number = index; let destinationEnd: number = index;
    if (this.read(index) === '<') {
      destinationStart = ++index;
      while (index < this.text.length && this.budget > 0) {
        const character: string = this.read(index);
        if (character === '>') { break; }
        if (character === '<' || character === '\r' || character === '\n') { return undefined; }
        if (character === '\\' && ASCII_ESCAPE.test(this.read(index + 1))) { index++; }
        index++;
      }
      if (this.read(index) !== '>') { return undefined; }
      destinationEnd = index++;
    } else {
      let depth: number = 0;
      while (index < this.text.length && this.budget > 0) {
        const character: string = this.read(index);
        if (character === '\\' && ASCII_ESCAPE.test(this.read(index + 1))) { index += 2; continue; }
        if (character === '(') { if (++depth > INLINE_DEPTH) { return undefined; } }
        else if (character === ')') { if (depth === 0) { break; } depth--; }
        else if (character.charCodeAt(0) <= 32 || character.charCodeAt(0) === 127) { break; }
        index++;
      }
      if (depth !== 0) { return undefined; }
      destinationEnd = index;
    }
    const afterDestination: number = index;
    index = this.skipSpace(index);
    if (index < 0) { return undefined; }
    let titleStart: number = index; let titleEnd: number = index;
    const quote: string = this.read(index);
    if (index > afterDestination && (quote === '"' || quote === "'" || quote === '(')) {
      const close: string = quote === '(' ? ')' : quote;
      titleStart = ++index;
      let lineOnlySpace: boolean = false;
      while (index < this.text.length && this.budget > 0) {
        const character: string = this.read(index);
        if (character === close) { break; }
        if (quote === '(' && character === '(') { return undefined; }
        if (character === '\\' && ASCII_ESCAPE.test(this.read(index + 1))) { index += 2; lineOnlySpace = false; continue; }
        if (character === '\r' || character === '\n') {
          if (lineOnlySpace) { return undefined; } lineOnlySpace = true;
          if (character === '\r' && this.read(index + 1) === '\n') { index++; }
        } else if (character !== ' ' && character !== '\t') { lineOnlySpace = false; }
        index++;
      }
      if (this.read(index) !== close) { return undefined; }
      titleEnd = index; index = this.skipSpace(index + 1);
    }
    if (index < 0 || this.read(index) !== ')') { return undefined; }
    return { end: index + 1, destination: this.decoded(destinationStart, destinationEnd),
      title: this.decoded(titleStart, titleEnd), label: '' };
  }
  private closeBracket(close: number): number {
    const bracket: InlineBracket | undefined = this.brackets.pop();
    if (bracket === undefined || !bracket.active) { return close; }
    let target: InlineTarget | undefined = this.read(close + 1) === '(' ? this.target(close + 1) : undefined;
    if (target === undefined) {
      let start: number = bracket.token.end; let end: number = close; let finish: number = close + 1;
      if (this.read(close + 1) === '[') {
        const labelEnd: number = this.labelEnd(close + 2);
        if (labelEnd >= 0) {
          if (labelEnd > close + 2) { start = close + 2; end = labelEnd; }
          finish = labelEnd + 1;
        }
      }
      if (end - start <= 999 && this.labelEnd(start) === end) {
        const label: string = this.label(start, end);
        const reference: MarkdownReference | undefined = this.context.references.get(label);
        if (reference !== undefined) {
          target = { end: finish, destination: reference.destination, title: reference.title, label: label };
        }
      }
    }
    if (target === undefined) { return close; }
    this.processDelimiters(bracket.bottom);
    const children: InlineToken[] = [];
    let child: InlineToken | undefined = bracket.token.next;
    let height: number = 1;
    while (child !== undefined) {
      this.context.work.inlineUnits++; children.push(child);
      height = Math.max(height, child.height + 1); child = child.next;
    }
    if (height > INLINE_DEPTH) { return close; }
    const token: InlineToken = new InlineToken(bracket.token.start, target.end);
    token.kind = bracket.image ? 'image' : 'link'; token.children = children; token.height = height;
    token.innerStart = bracket.token.end; token.innerEnd = close;
    token.destination = target.destination; token.title = target.title; token.label = target.label;
    this.tail = bracket.token.previous === undefined ? this.root : bracket.token.previous;
    this.tail.next = undefined; this.append(token);
    if (!bracket.image) {
      for (let index: number = 0; index < this.brackets.length; index++) {
        this.context.work.inlineUnits++;
        if (!this.brackets[index].image) { this.brackets[index].active = false; }
      }
    }
    return target.end;
  }

  private processDelimiters(bottom: InlineDelimiter): void {
    const floors: Map<string, number> = new Map<string, number>();
    let closer: InlineDelimiter | undefined = bottom.next;
    while (closer !== undefined) {
      this.context.work.inlineUnits++;
      if (!closer.closes) { closer = closer.next; continue; }
      const single: boolean = closer.symbol === '^' || (closer.symbol === '~' && closer.original === 1);
      const key: string = closer.symbol + (closer.opens ? 'o' : 'c') + (single ? 's' : closer.original % 3);
      const floor: number = floors.get(key) === undefined ? bottom.sequence : floors.get(key)!;
      let opener: InlineDelimiter | undefined = closer.previous;
      while (opener !== undefined && opener.sequence > floor && this.budget > 0) {
        this.context.work.inlineUnits++; this.budget--;
        const same: boolean = opener.symbol === closer.symbol && opener.opens &&
          (closer.symbol !== '~' || (opener.original === 1) === single);
        const odd: boolean = (closer.symbol === '*' || closer.symbol === '_') &&
          (opener.closes || closer.opens) && (opener.original + closer.original) % 3 === 0 &&
          (opener.original % 3 !== 0 || closer.original % 3 !== 0);
        const spaced: boolean = single && this.spaces[closer.token.start] !== this.spaces[opener.token.end];
        if (same && !odd && !spaced && (single || closer.symbol !== '~' ||
          (opener.length >= 2 && closer.length >= 2))) { break; }
        opener = opener.previous;
      }
      if (opener === undefined || opener.sequence <= floor || this.budget <= 0) {
        floors.set(key, closer.previous === undefined ? bottom.sequence : closer.previous.sequence);
        const next: InlineDelimiter | undefined = closer.next;
        if (!closer.opens) { this.removeDelimiter(closer); }
        closer = next; continue;
      }
      const count: number = single ? 1 : (opener.length >= 2 && closer.length >= 2 ? 2 : 1);
      const children: InlineToken[] = [];
      let child: InlineToken | undefined = opener.token.next;
      let height: number = 1;
      while (child !== undefined && child !== closer.token) {
        this.context.work.inlineUnits++; children.push(child);
        height = Math.max(height, child.height + 1); child = child.next;
      }
      if (height > INLINE_DEPTH) {
        const next: InlineDelimiter | undefined = closer.next;
        this.removeDelimiter(closer); closer = next; continue;
      }
      const token: InlineToken = new InlineToken(opener.token.end - count, closer.token.start + count);
      token.kind = closer.symbol === '^' ? 'superscript' : closer.symbol === '~' ?
        (single ? 'subscript' : 'strikethrough') : closer.symbol === '=' ? 'highlight' :
        (count === 2 ? 'strong' : 'emphasis');
      token.children = children; token.height = height;
      token.innerStart = opener.token.end; token.innerEnd = closer.token.start;
      opener.token.end -= count; opener.token.innerEnd = opener.token.end;
      closer.token.start += count; closer.token.innerStart = closer.token.start;
      token.previous = opener.token; token.next = closer.token;
      opener.token.next = token; closer.token.previous = token;
      let removed: InlineDelimiter | undefined = opener.next;
      while (removed !== undefined && removed !== closer) {
        this.context.work.inlineUnits++;
        const next: InlineDelimiter | undefined = removed.next; this.removeDelimiter(removed); removed = next;
      }
      opener.length -= count; closer.length -= count;
      if (opener.length === 0) { this.removeToken(opener.token); this.removeDelimiter(opener); }
      if (closer.length === 0) {
        const next: InlineDelimiter | undefined = closer.next;
        this.removeToken(closer.token); this.removeDelimiter(closer); closer = next;
      }
    }
    let removed: InlineDelimiter | undefined = bottom.next;
    while (removed !== undefined) {
      this.context.work.inlineUnits++;
      const next: InlineDelimiter | undefined = removed.next; this.removeDelimiter(removed); removed = next;
    }
  }

  private domainValid(start: number, end: number, bare: boolean): boolean {
    let labelStart: number = start; let dots: number = 0;
    for (let index: number = start; index <= end; index++) {
      const character: string = index === end ? '.' : this.read(index);
      if (character === '.') {
        const length: number = index - labelStart;
        if (length < 1 || length > 63 || this.read(labelStart) === '-' || this.read(index - 1) === '-') { return false; }
        if (index < end) { dots++; labelStart = index + 1; }
      } else if (!/[a-zA-Z0-9-]/.test(character)) { return false; }
    }
    if (!bare) { return true; }
    if (dots === 0 || end - labelStart < 2) { return false; }
    for (let index: number = labelStart; index < end; index++) {
      if (!inlineAsciiLetter(this.read(index))) { return false; }
    }
    return true;
  }
  private emailValid(start: number, end: number): boolean {
    let index: number = start;
    while (index < end && EMAIL_LOCAL.test(this.read(index))) { index++; }
    return index > start && this.read(index) === '@' && this.domainValid(index + 1, end, false);
  }
  private angle(start: number): InlineToken | undefined {
    let index: number = start + 1;
    while (index < this.text.length && this.budget > 0 &&
      !/[<>\x00-\x20\x7f]/.test(this.read(index))) { index++; }
    if (this.read(index) === '>') {
      const value: string = this.raw(start + 1, index);
      this.context.work.inlineUnits += value.length * 2;
      const uri: boolean = /^[a-zA-Z][a-zA-Z0-9+.-]{1,31}:/.test(value);
      const email: boolean = !uri && this.emailValid(start + 1, index);
      if (uri || email) {
        const token: InlineToken = new InlineToken(start, index + 1);
        token.kind = 'link'; token.destination = email ? 'mailto:' + value : value;
        if (email) { this.context.work.materializedUnits += token.destination.length; }
        token.innerStart = start + 1; token.innerEnd = index; token.height = 1;
        const child: InlineToken = new InlineToken(start + 1, index); child.value = value; token.children = [child];
        for (let bracket: number = 0; bracket < this.brackets.length; bracket++) {
          this.context.work.inlineUnits++;
          if (!this.brackets[bracket].image) { this.brackets[bracket].active = false; }
        }
        return token;
      }
    }
    const end: number = this.htmlEnd(start);
    if (end < 0) { return undefined; }
    const token: InlineToken = new InlineToken(start, end);
    token.kind = 'htmlInline'; token.value = this.raw(start, end); return token;
  }
  private findClosing(start: number, closing: string): number {
    for (let index: number = start; index < this.text.length && this.budget > 0; index++) {
      if (this.matches(index, closing)) { return index + closing.length; }
    }
    return -1;
  }
  private htmlEnd(start: number): number {
    if (this.matches(start, '<!--')) {
      if (this.matches(start, '<!-->')) { return start + 5; }
      if (this.matches(start, '<!--->')) { return start + 6; }
      return this.findClosing(start + 4, '-->');
    }
    if (this.matches(start, '<?')) { return this.findClosing(start + 2, '?>'); }
    if (this.matches(start, '<![CDATA[')) { return this.findClosing(start + 9, ']]>'); }
    if (this.matches(start, '<!') && inlineAsciiLetter(this.read(start + 2))) {
      return this.findClosing(start + 3, '>');
    }
    let index: number = start + 1;
    const closing: boolean = this.read(index) === '/';
    if (closing) { index++; }
    if (!inlineAsciiLetter(this.read(index))) { return -1; }
    while (/[a-zA-Z0-9-]/.test(this.read(index))) { index++; }
    while (index < this.text.length && this.budget > 0) {
      const before: number = index; index = this.skipSpace(index);
      if (index < 0) { return -1; }
      if (this.read(index) === '>') { return index + 1; }
      if (!closing && this.read(index) === '/' && this.read(index + 1) === '>') { return index + 2; }
      if (closing || index === before || !/[a-zA-Z_:]/.test(this.read(index))) { return -1; }
      index++;
      while (/[a-zA-Z0-9_.:-]/.test(this.read(index))) { index++; }
      const afterName: number = index; index = this.skipSpace(index);
      if (index < 0) { return -1; }
      if (this.read(index) !== '=') { index = afterName; continue; }
      index = this.skipSpace(index + 1);
      if (index < 0) { return -1; }
      const quote: string = this.read(index);
      if (quote === '"' || quote === "'") {
        index = this.findClosing(index + 1, quote);
        if (index < 0) { return -1; }
      } else {
        const valueStart: number = index;
        while (index < this.text.length && this.budget > 0 && !/[ \t\r\n"'=<>`]/.test(this.read(index))) { index++; }
        if (index === valueStart) { return -1; }
      }
    }
    return -1;
  }

  private bare(start: number, limit: number): InlineBare {
    const result: InlineBare = { end: start, next: start + 1, destination: '' };
    const previous: string = this.read(start - 1);
    if (/[a-zA-Z0-9_]/.test(previous)) { return result; }
    let prefix: number = this.matches(start, 'https://', true) ? 8 :
      this.matches(start, 'http://', true) ? 7 : this.matches(start, 'www.', true) ? 4 : 0;
    let index: number = start;
    if (prefix > 0) {
      index += prefix; const host: number = index; let balance: number = 0;
      while (index < limit && this.budget > 0) {
        const character: string = this.read(index);
        if (inlineWhite(character) || /[<>"'`\[\]*，。！？；：（）【】《》]/.test(character)) { break; }
        if (character === '(') { balance++; }
        if (character === ')') { if (balance === 0) { break; } balance--; }
        index++;
      }
      result.next = Math.max(start + 1, index);
      while (index > host && /[.,:;!?]/.test(this.read(index - 1))) {
        if (this.read(index - 1) === ';') {
          let amp: number = index - 2;
          while (amp >= host && index - amp <= 34 && /[a-zA-Z0-9#]/.test(this.read(amp))) { amp--; }
          if (this.read(amp) === '&') {
            const raw: string = this.raw(amp, index);
            const decoded: string = decodeMarkdownEntities(raw);
            this.context.work.inlineUnits += raw.length; this.context.work.materializedUnits += decoded.length;
            if (raw !== decoded) { break; }
          }
        }
        index--;
      }
      if (index === host) { return result; }
      result.end = index; result.destination = (prefix === 4 ? 'http://' : '') + this.decoded(start, index);
      if (prefix === 4) { this.context.work.materializedUnits += result.destination.length; }
      return result;
    }
    if (!EMAIL_LOCAL.test(this.read(start)) || EMAIL_LOCAL.test(previous)) { return result; }
    while (index < limit && EMAIL_LOCAL.test(this.read(index)) && this.budget > 0) { index++; }
    result.next = Math.max(start + 1, index);
    if (this.read(index) !== '@') { return result; }
    const domain: number = ++index;
    while (index < limit && DOMAIN_CHAR.test(this.read(index)) && this.budget > 0) { index++; }
    result.next = index;
    while (index > domain && this.read(index - 1) === '.') { index--; }
    if (!this.domainValid(domain, index, true)) { return result; }
    result.end = index; result.destination = 'mailto:' + this.raw(start, index);
    this.context.work.materializedUnits += result.destination.length; return result;
  }
  private linkText(start: number, end: number): InlineToken {
    const token: InlineToken = new InlineToken(start, end);
    token.value = decodeMarkdownEntities(this.raw(start, end));
    this.context.work.inlineUnits += end - start;
    this.context.work.materializedUnits += token.value.length; return token;
  }
  private linkCandidate(token: InlineToken): boolean {
    return token.kind === 'text' && (token.value === undefined || this.read(token.start) === '&');
  }
  private linkify(tokens: InlineToken[], disabled: boolean): InlineToken[] {
    if (disabled) { return tokens; }
    const result: InlineToken[] = [];
    for (let tokenIndex: number = 0; tokenIndex < tokens.length; tokenIndex++) {
      const token: InlineToken = tokens[tokenIndex];
      if (!this.linkCandidate(token)) { result.push(token); continue; }
      let end: number = token.end;
      while (tokenIndex + 1 < tokens.length && this.linkCandidate(tokens[tokenIndex + 1]) &&
        tokens[tokenIndex + 1].start === end) {
        end = tokens[++tokenIndex].end; this.context.work.inlineUnits++;
      }
      let emitted: number = token.start; let index: number = token.start;
      while (index < end && this.budget > 0) {
        const candidate: InlineBare = this.bare(index, end);
        if (candidate.end > index) {
          if (index > emitted) { result.push(this.linkText(emitted, index)); }
          const link: InlineToken = new InlineToken(index, candidate.end);
          link.kind = 'link'; link.destination = candidate.destination; link.height = 1;
          link.children = [this.linkText(index, candidate.end)]; result.push(link);
          emitted = candidate.end; index = emitted;
        } else { index = Math.max(index + 1, candidate.next); }
      }
      if (emitted < end) { result.push(this.linkText(emitted, end)); }
    }
    return result;
  }
  private mappedParts(start: number, end: number): MarkdownTextSlice[] {
    const result: MarkdownTextSlice[] = [];
    let index: number = start;
    while (index < end) {
      const begin: number = index++;
      this.context.work.inlineUnits++;
      while (index < end) {
        this.context.work.inlineUnits++;
        if (this.positions[index] !== this.positions[index - 1] + 1) { break; }
        index++;
      }
      result.push({ text: this.raw(begin, index), start: this.positions[begin] });
    }
    return result;
  }
  private node(token: InlineToken): MarkdownNode {
    this.context.work.nodeVisits++;
    const start: number = token.start < this.positions.length ? this.positions[token.start] :
      (this.positions.length === 0 ? 0 : this.positions[this.positions.length - 1] + 1);
    const end: number = token.end > token.start ? this.positions[token.end - 1] + 1 : start;
    this.context.work.inlineUnits += 2;
    const node: MarkdownNode = markdownNode(token.kind, start, end);
    node.parts = this.mappedParts(token.innerStart, token.innerEnd);
    node.destination = token.destination; node.title = token.title; node.label = token.label;
    node.closed = token.closed; node.startNumber = token.number;
    return node;
  }
  private materialize(input: InlineToken[], insideLink: boolean, subSpace: boolean): MarkdownNode[] {
    const tokens: InlineToken[] = this.linkify(input, insideLink);
    const result: MarkdownNode[] = [];
    for (let index: number = 0; index < tokens.length; index++) {
      const token: InlineToken = tokens[index];
      if (token.kind === 'text') {
        const chunks: string[] = []; let end: number = token.end;
        let current: InlineToken = token;
        while (true) {
          this.context.work.inlineUnits++;
          chunks.push(current.escapedSpace && subSpace ? ' ' :
            current.value === undefined ? this.raw(current.start, current.end) : current.value);
          end = current.end;
          if (index + 1 >= tokens.length || tokens[index + 1].kind !== 'text' || tokens[index + 1].start !== end) { break; }
          current = tokens[++index];
        }
        const merged: InlineToken = new InlineToken(token.start, end);
        const node: MarkdownNode = this.node(merged); node.text = chunks.join('');
        this.context.work.materializedUnits += node.text.length;
        result.push(node); continue;
      }
      const node: MarkdownNode = this.node(token);
      node.text = token.value === undefined ? '' : token.value;
      node.children = this.materialize(token.children, insideLink || token.kind === 'link',
        subSpace || token.kind === 'subscript' || token.kind === 'superscript');
      if (token.kind === 'image') { node.text = this.plain(node.children); }
      result.push(node);
    }
    return result;
  }
  private plain(nodes: MarkdownNode[]): string {
    const chunks: string[] = [];
    for (let index: number = 0; index < nodes.length; index++) {
      const node: MarkdownNode = nodes[index]; this.context.work.inlineUnits++;
      chunks.push(node.kind === 'softBreak' || node.kind === 'hardBreak' ? '\n' :
        node.children.length > 0 ? this.plain(node.children) : node.text);
    }
    const value: string = chunks.join(''); this.context.work.materializedUnits += value.length; return value;
  }
}

export function parseMarkdownInline(parts: MarkdownTextSlice[], context: MarkdownInlineContext): MarkdownNode[] {
  return new MarkdownInlineParser(parts, context).parse();
}
