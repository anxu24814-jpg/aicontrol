/**
 * 专用、有界、无依赖的词法着色，不解释 Markdown，也不是编译器/parser。选型：OHPM 无可用
 * 候选、highlight.js 公开结果为 HTML 而非 token、旧 Markdown 库 bytecode 非公开 API——
 * 本件原创扫描，不复制第三方规则/实现。
 * 仅承诺常用词法层：注释、字符串、数字、关键字、类型、HTML标签/属性、CSS属性。语言族 21
 *（U3 补 yaml/toml/ini/sql/go/rust/kotlin/dart/lua/dockerfile），注释前缀按语言分族表，键值
 * 族（yaml/toml/ini）着色属性键。diff/udiff 归一 + 行级五类分派（U4：+++ / --- 文件头、
 * @@ hunk 头、+ 增行、- 删行、其余 plain；整行含行尾换行作单 run、同类行由 emit 合并，
 * 不做 +N/-N 计数行）。
 * 模板插值、正则与除法歧义、C++原始串、shell展开/heredoc 不作完整语法解释；go/rust/kotlin
 * 原始串与 lua 长括号串按普通字符，rust 词首 'x 视为生命周期。未闭串/注释逐字保留；每次
 * 内容变化重新扫描本块，不伪称流式增量。输出按 UTF-16 连续范围切原文，不解实体、不归一
 * 换行、不补闭合。字符读取有硬预算、Span 有硬上限；越限整块退纯源码，不静默截断。
 */
export type MarkdownHighlightKind = 'plain' | 'keyword' | 'type' | 'string' | 'comment' |
  'number' | 'property' | 'tag' | 'addition' | 'deletion' | 'hunk' | 'fileHeader';
export type MarkdownHighlightStatus = 'highlighted' | 'plain' | 'limited' | 'failed';

export interface MarkdownHighlightRun {
  start: number;
  end: number;
  text: string;
  kind: MarkdownHighlightKind;
}

export interface MarkdownHighlightResult {
  runs: MarkdownHighlightRun[];
  language: string;
  status: MarkdownHighlightStatus;
  message: string;
  /** 本轮实际charAt读取次数，含前瞻/回看；不是CPU指令数。 */
  readUnits: number;
}

// 保护主线程同步词法工作与原生 Span 物化量，不是设备帧时保证。实测（Node24/Ultra9 285H）
// 32K HTML 文本 P95 约 2.29ms，同步预算取 32K；1024 是保守片段预算而非实测 ArkUI 安全线
//（设备布局/主题观感待集中验收）。
export const MARKDOWN_HIGHLIGHT_MAX_UNITS: number = 32768;
export const MARKDOWN_HIGHLIGHT_MAX_RUNS: number = 1024;
const MAX_READS: number = MARKDOWN_HIGHLIGHT_MAX_UNITS * 40;
const MAX_LANGUAGE_UNITS: number = 128;

const JS_KEYWORDS: Set<string> = new Set<string>(('as async await break case catch class const continue ' +
  'debugger declare default delete do else enum export extends finally for from function get if implements ' +
  'import in infer instanceof interface keyof let namespace new of private protected public readonly return ' +
  'satisfies set static struct super switch this throw try type typeof var void while with yield ' +
  'abstract constructor override package true false null undefined NaN Infinity').split(' '));
const C_KEYWORDS: Set<string> = new Set<string>(('alignas alignof asm auto break case catch class concept const ' +
  'consteval constexpr constinit continue co_await co_return co_yield decltype default delete do else enum ' +
  'explicit export extern final for friend goto if inline mutable namespace new noexcept operator override ' +
  'private protected public register reinterpret_cast requires return signed sizeof static static_assert ' +
  'static_cast struct switch template this thread_local throw try typedef typeid typename union unsigned ' +
  'using virtual volatile while abstract assert extends finally implements import instanceof interface ' +
  'native package strictfp super synchronized throws transient var record sealed permits yield ' +
  'true false null nullptr').split(' '));
const PY_KEYWORDS: Set<string> = new Set<string>(('and as assert async await break case class continue def del ' +
  'elif else except finally for from global if import in is lambda match nonlocal not or pass raise return ' +
  'try while with yield True False None').split(' '));
const SH_KEYWORDS: Set<string> = new Set<string>(('if then else elif fi for while until do done in case esac ' +
  'function select time coproc export local readonly return exit break continue source alias unalias ' +
  'set unset shift trap exec eval test echo printf read cd pwd').split(' '));
const GO_KEYWORDS: Set<string> = new Set<string>(('break case chan const continue default defer else ' +
  'fallthrough for func go goto if import interface map package range return select struct switch type var ' +
  'true false nil iota').split(' '));
const RUST_KEYWORDS: Set<string> = new Set<string>(('as async await break const continue crate dyn else enum ' +
  'extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super ' +
  'trait true type unsafe use where while').split(' '));
const KOTLIN_KEYWORDS: Set<string> = new Set<string>(('as break by catch class companion const constructor ' +
  'continue crossinline data do dynamic else enum external false final finally for fun get if import in infix ' +
  'init inline interface internal is lateinit null object open operator out override package private ' +
  'protected public reified return sealed set super suspend this throw true try typealias val var vararg ' +
  'when where while').split(' '));
const DART_KEYWORDS: Set<string> = new Set<string>(('abstract as assert async await break case catch class ' +
  'const continue covariant default deferred do dynamic else enum export extends extension external factory ' +
  'false final finally for get hide if implements import in interface is late library mixin new null on ' +
  'operator part required rethrow return set show super switch sync this throw true try typedef var void ' +
  'while with yield').split(' '));
const LUA_KEYWORDS: Set<string> = new Set<string>(('and break do else elseif end false for function goto if ' +
  'in local nil not or repeat return then true until while').split(' '));
const SQL_KEYWORDS: Set<string> = new Set<string>(('alter and any as asc begin between by case check column ' +
  'commit constraint create cross cursor database declare default delete desc distinct drop else end exists ' +
  'foreign from full group having in index inner insert intersect into is join key left like limit not null ' +
  'offset on or order outer primary procedure references replace right rollback select set table then ' +
  'transaction trigger union unique update values view when where with').split(' '));
const DOCKERFILE_KEYWORDS: Set<string> = new Set<string>(('add arg as cmd copy entrypoint env expose from ' +
  'healthcheck label maintainer onbuild run shell stopsignal user volume workdir').split(' '));
const YAML_KEYWORDS: Set<string> = new Set<string>('true false null yes no on off'.split(' '));
const TOML_KEYWORDS: Set<string> = new Set<string>('true false inf nan'.split(' '));
const TYPE_WORDS: Set<string> = new Set<string>(('boolean bool byte char double float int long short void ' +
  'string number bigint symbol object any unknown never undefined Array Map Set Promise Record String ' +
  'Number Boolean Object Integer List Optional size_t ssize_t int8_t int16_t int32_t int64_t ' +
  'uint8_t uint16_t uint32_t uint64_t str bytes dict tuple list set complex ' +
  'float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 uintptr rune ' +
  'i8 i16 i32 i64 u8 u16 u32 u64 usize isize f32 f64 Vec Option Result Box Rc Arc HashMap HashSet ' +
  'Int Long Short Byte Char Boolean Double Float Any Unit').split(' '));
// 注释前缀按语言分族：// 族与块注释族见 SLASH/BLOCK 两表；# 族须行首或空白后（python 沿旧例任意
// 位置、shell 另认 ;|&() 命令边界后）；--族 = sql/lua；ini 另认 ; 行注释。
const SLASH_COMMENT_LANGS: Set<string> = new Set<string>(
  'javascript typescript java c cpp go rust kotlin dart'.split(' '));
const HASH_COMMENT_LANGS: Set<string> = new Set<string>('shell yaml toml dockerfile ini'.split(' '));
const DASH_COMMENT_LANGS: Set<string> = new Set<string>('sql lua'.split(' '));
const BLOCK_COMMENT_LANGS: Set<string> = new Set<string>(
  'javascript typescript java c cpp go rust kotlin dart sql'.split(' '));
// 关键字大小写不敏感、查小写表的 = sql/dockerfile/yaml（go/rust/kotlin/dart 等大小写敏感原词查）。
const LOWERCASE_KEYWORD_LANGS: Set<string> = new Set<string>('sql dockerfile yaml'.split(' '));

function digit(character: string): boolean { return character >= '0' && character <= '9'; }
function letter(character: string): boolean {
  return (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z');
}
function wordStart(character: string): boolean { return letter(character) || character === '_' || character === '$'; }
function wordPart(character: string): boolean { return wordStart(character) || digit(character); }
function space(character: string): boolean {
  return character === ' ' || character === '\t' || character === '\r' || character === '\n' || character === '\f';
}
function namePart(character: string): boolean {
  return wordPart(character) || character === '-' || character === ':' || character === '.';
}

/** 只取围栏info首项，限定标签长度，避免为未知语言扫描/复制整段超长info。 */
function languageOf(info: string): string {
  let start: number = 0;
  while (start < info.length && start < MAX_LANGUAGE_UNITS && space(info.charAt(start))) { start++; }
  let end: number = start;
  while (end < info.length && end < MAX_LANGUAGE_UNITS && !space(info.charAt(end))) { end++; }
  if (end === MAX_LANGUAGE_UNITS && end < info.length && !space(info.charAt(end))) { return ''; }
  let name: string = info.substring(start, end).toLowerCase();
  if (name.startsWith('language-')) { name = name.substring(9); }
  switch (name) {
    case 'js': case 'javascript': case 'mjs': case 'cjs': return 'javascript';
    case 'ts': case 'typescript': case 'arkts': case 'ets': return 'typescript';
    case 'json': return 'json';
    case 'py': case 'python': case 'python3': return 'python';
    case 'java': return 'java';
    case 'c': case 'h': return 'c';
    case 'cpp': case 'c++': case 'cc': case 'cxx': case 'hpp': return 'cpp';
    case 'sh': case 'shell': case 'bash': case 'zsh': return 'shell';
    case 'html': case 'htm': case 'xml': case 'svg': return 'html';
    case 'css': return 'css';
    case 'yaml': case 'yml': return 'yaml';
    case 'toml': return 'toml';
    case 'ini': case 'conf': case 'cfg': return 'ini';
    case 'sql': case 'mysql': case 'postgres': case 'postgresql': case 'sqlite': return 'sql';
    case 'go': case 'golang': return 'go';
    case 'rust': case 'rs': return 'rust';
    case 'kotlin': case 'kt': return 'kotlin';
    case 'dart': return 'dart';
    case 'lua': return 'lua';
    case 'dockerfile': case 'docker': return 'dockerfile';
    case 'diff': case 'udiff': return 'diff';
    case 'text': case 'txt': case 'plain': case 'plaintext': return 'plain';
    default: return '';
  }
}

function plainResult(source: string, language: string, status: MarkdownHighlightStatus,
  message: string, reads: number = 0): MarkdownHighlightResult {
  const runs: MarkdownHighlightRun[] = [];
  if (source.length > 0) { runs.push({ start: 0, end: source.length, text: source, kind: 'plain' }); }
  return { runs: runs, language: language, status: status, message: message, readUnits: reads };
}

class HighlightScanner {
  private source: string;
  private language: string;
  private cursor: number = 0;
  private runs: MarkdownHighlightRun[] = [];
  private htmlTag: boolean = false;
  private htmlName: boolean = false;
  private cssValue: boolean = false;
  private cssDepth: number = 0;
  private regexAllowed: boolean = true;
  readUnits: number = 0;
  limited: boolean = false;

  constructor(source: string, language: string) { this.source = source; this.language = language; }

  private read(index: number): string {
    if (this.readUnits >= MAX_READS) { this.limited = true; throw new Error('高亮读取超出预算'); }
    if (index < 0 || index >= this.source.length) { return ''; }
    this.readUnits++;
    return this.source.charAt(index);
  }

  private matches(index: number, value: string): boolean {
    for (let offset: number = 0; offset < value.length; offset++) {
      if (this.read(index + offset) !== value.charAt(offset)) { return false; }
    }
    return true;
  }

  private lineEnd(start: number): number {
    let end: number = start;
    while (end < this.source.length && this.read(end) !== '\n' && this.read(end) !== '\r') { end++; }
    return end;
  }

  private until(start: number, closing: string): number {
    let end: number = start;
    while (end < this.source.length) {
      if (this.matches(end, closing)) { return end + closing.length; }
      end++;
    }
    return end;
  }

  private quoted(start: number, quote: string, multiline: boolean, escapes: boolean): number {
    let end: number = start + quote.length;
    while (end < this.source.length) {
      const character: string = this.read(end);
      if (escapes && character === '\\') { end = Math.min(this.source.length, end + 2); continue; }
      if (this.matches(end, quote)) { return end + quote.length; }
      // 普通单行坏串止于换行，避免流式未闭串把后续整段代码全吞为同一颜色。
      if (!multiline && (character === '\n' || character === '\r')) { return end; }
      end++;
    }
    return end;
  }

  private emit(end: number, kind: MarkdownHighlightKind): void {
    if (end <= this.cursor || end > this.source.length) { throw new Error('高亮范围无进展'); }
    const last: MarkdownHighlightRun | undefined = this.runs.length > 0 ? this.runs[this.runs.length - 1] : undefined;
    if (last !== undefined && last.kind === kind) {
      last.end = end;
    } else {
      if (this.runs.length >= MARKDOWN_HIGHLIGHT_MAX_RUNS) {
        this.limited = true;
        throw new Error('高亮片段超出预算');
      }
      this.runs.push({ start: this.cursor, end: end, text: '', kind: kind });
    }
    this.cursor = end;
  }

  private numberEnd(start: number): number {
    let end: number = start;
    if (this.read(end) === '0' && 'xXbBoO'.includes(this.read(end + 1)) && this.read(end + 1) !== '') {
      const prefix: string = this.read(end + 1).toLowerCase();
      end += 2;
      while (end < this.source.length) {
        const character: string = this.read(end).toLowerCase();
        const valid: boolean = character === '_' || (prefix === 'x' ? digit(character) ||
          (character >= 'a' && character <= 'f') : prefix === 'b' ? character === '0' || character === '1' :
          character >= '0' && character <= '7');
        if (!valid) { break; }
        end++;
      }
    } else {
      while (digit(this.read(end)) || this.read(end) === '_') { end++; }
      if (this.read(end) === '.' && this.read(end + 1) !== '.') {
        end++;
        while (digit(this.read(end)) || this.read(end) === '_') { end++; }
      }
      if (this.read(end) === 'e' || this.read(end) === 'E') {
        let exponent: number = end + 1;
        if (this.read(exponent) === '+' || this.read(exponent) === '-') { exponent++; }
        if (digit(this.read(exponent))) {
          end = exponent + 1;
          while (digit(this.read(end)) || this.read(end) === '_') { end++; }
        }
      }
    }
    if (this.language === 'javascript' || this.language === 'typescript') {
      if (this.read(end) === 'n') { end++; }
    }
    return end;
  }

  private wordEnd(start: number, names: boolean = false): number {
    let end: number = start;
    while (end < this.source.length && (names ? namePart(this.read(end)) : wordPart(this.read(end)))) { end++; }
    return end;
  }

  private wordKind(word: string): MarkdownHighlightKind {
    if (this.language === 'json') { return word === 'true' || word === 'false' || word === 'null' ? 'keyword' : 'plain'; }
    if (this.language === 'shell') { return SH_KEYWORDS.has(word) ? 'keyword' : 'plain'; }
    const keywords: Set<string> | undefined = this.keywords();
    const lookup: string = LOWERCASE_KEYWORD_LANGS.has(this.language) ? word.toLowerCase() : word;
    if (keywords !== undefined && keywords.has(lookup)) { return 'keyword'; }
    return TYPE_WORDS.has(word) ? 'type' : 'plain';
  }

  /** 各语言关键字表；json/shell 单列在前（无类型回退），ini 无关键字返回 undefined。 */
  private keywords(): Set<string> | undefined {
    switch (this.language) {
      case 'python': return PY_KEYWORDS;
      case 'yaml': return YAML_KEYWORDS;
      case 'toml': return TOML_KEYWORDS;
      case 'sql': return SQL_KEYWORDS;
      case 'lua': return LUA_KEYWORDS;
      case 'go': return GO_KEYWORDS;
      case 'rust': return RUST_KEYWORDS;
      case 'kotlin': return KOTLIN_KEYWORDS;
      case 'dart': return DART_KEYWORDS;
      case 'dockerfile': return DOCKERFILE_KEYWORDS;
      case 'javascript': case 'typescript': return JS_KEYWORDS;
      case 'java': case 'c': case 'cpp': return C_KEYWORDS;
      default: return undefined;
    }
  }

  /** 行注释前缀分派（分族口径见上方表注释）。 */
  private isLineComment(start: number): boolean {
    const character: string = this.read(start);
    if (character === '#') {
      if (this.language === 'python') { return true; }
      if (!HASH_COMMENT_LANGS.has(this.language)) { return false; }
      if (this.language === 'shell') {
        return start === 0 || space(this.read(start - 1)) || ';|&()'.includes(this.read(start - 1));
      }
      return start === 0 || space(this.read(start - 1));
    }
    if (character === '-' && DASH_COMMENT_LANGS.has(this.language) && this.read(start + 1) === '-') { return true; }
    if (character === ';' && this.language === 'ini') { return true; }
    if (character === '/' && SLASH_COMMENT_LANGS.has(this.language) && this.read(start + 1) === '/') { return true; }
    return false;
  }

  /** 键值族（yaml/toml/ini）单词扫到连字符/点整体（`my-key`/`a.b` 作一个键名）。 */
  private keyEnd(start: number): number {
    let end: number = start;
    while (end < this.source.length) {
      const character: string = this.read(end);
      if (wordPart(character)) { end++; continue; }
      if ((character === '-' || character === '.') && wordPart(this.read(end + 1))) { end++; continue; }
      break;
    }
    return end;
  }

  /** 键值族单词后越过空白遇 =（toml/ini）或 : 后随空白/行尾（yaml 冒号语义，避开 URL 的 ://）即属性键。 */
  private keySeparatorAfter(end: number): boolean {
    let after: number = end;
    while (space(this.read(after))) { after++; }
    const separator: string = this.read(after);
    if (separator === '=') { return true; }
    return separator === ':' && (space(this.read(after + 1)) || this.read(after + 1) === '');
  }

  /** 仅在表达式起始位置识别常见JS正则，完整语法歧义不靠回溯猜测。 */
  private regexEnd(start: number): number {
    let end: number = start + 1;
    let inClass: boolean = false;
    while (end < this.source.length) {
      const character: string = this.read(end);
      if (character === '\n' || character === '\r') { return end; }
      if (character === '\\') { end = Math.min(this.source.length, end + 2); continue; }
      if (character === '[') { inClass = true; }
      if (character === ']') { inClass = false; }
      if (character === '/' && !inClass) {
        end++;
        while (letter(this.read(end))) { end++; }
        return end;
      }
      end++;
    }
    return end;
  }

  private code(): void {
    const start: number = this.cursor;
    const character: string = this.read(start);
    const shell: boolean = this.language === 'shell';
    const python: boolean = this.language === 'python';
    const json: boolean = this.language === 'json';
    const javascript: boolean = this.language === 'javascript' || this.language === 'typescript';
    const keyValue: boolean = this.language === 'yaml' || this.language === 'toml' || this.language === 'ini';
    if (space(character)) {
      let end: number = start + 1;
      while (space(this.read(end))) { end++; }
      this.emit(end, 'plain'); return;
    }
    if (this.isLineComment(start)) {
      this.emit(this.lineEnd(start), 'comment'); return;
    }
    if (BLOCK_COMMENT_LANGS.has(this.language) && this.matches(start, '/*')) {
      this.emit(this.until(start + 2, '*/'), 'comment'); return;
    }
    // rust 词首 'x 是生命周期标注而非未闭字符串：单词后无闭引号即生命周期（含 'static），避免吞行。
    if (this.language === 'rust' && character === "'" && wordStart(this.read(start + 1))) {
      const wordAfter: number = this.wordEnd(start + 1);
      if (this.read(wordAfter) !== "'") {
        this.emit(wordAfter, 'type'); this.regexAllowed = false; return;
      }
    }
    if (character === '"' || (!json && character === "'") || ((javascript || shell) && character === '`')) {
      let quote: string = character;
      if ((python || this.language === 'java') && this.matches(start, character + character + character)) {
        quote = character + character + character;
      }
      const end: number = this.quoted(start, quote, quote.length === 3 || character === '`' || shell,
        !(shell && character === "'"));
      let kind: MarkdownHighlightKind = 'string';
      // json/yaml/toml 里闭引号串后随 : 或 =（toml）的是键名，按属性着色。
      if ((json || this.language === 'yaml' || this.language === 'toml') && this.read(end - 1) === quote.charAt(0)) {
        let after: number = end;
        while (space(this.read(after))) { after++; }
        const separator: string = this.read(after);
        if (separator === ':' || (separator === '=' && !json)) { kind = 'property'; }
      }
      this.emit(end, kind); this.regexAllowed = false; return;
    }
    if ((shell || this.language === 'dockerfile') && character === '$') {
      let end: number = start + 1;
      if (this.read(end) === '{') {
        end = this.until(end + 1, '}');
      } else if (wordPart(this.read(end))) {
        end = this.wordEnd(end);
      } else if (this.read(end) !== '' && '?@*#$!-'.includes(this.read(end))) {
        end++;
      }
      this.emit(end, 'property'); return;
    }
    if (javascript && character === '/' && this.regexAllowed) {
      this.emit(this.regexEnd(start), 'string'); this.regexAllowed = false; return;
    }
    if (character === '@' && (javascript || python || this.language === 'java' ||
      this.language === 'kotlin' || this.language === 'dart') && wordStart(this.read(start + 1))) {
      this.emit(this.wordEnd(start + 1), 'keyword'); this.regexAllowed = false; return;
    }
    if (character === '#' && (this.language === 'c' || this.language === 'cpp')) {
      let end: number = start + 1;
      while (this.read(end) === ' ' || this.read(end) === '\t') { end++; }
      if (wordStart(this.read(end))) { this.emit(this.wordEnd(end), 'keyword'); return; }
    }
    if (digit(character) || (character === '.' && digit(this.read(start + 1)))) {
      this.emit(this.numberEnd(start), 'number'); this.regexAllowed = false; return;
    }
    if (wordStart(character)) {
      const end: number = keyValue ? this.keyEnd(start) : this.wordEnd(start);
      const word: string = this.source.substring(start, end);
      let kind: MarkdownHighlightKind = this.wordKind(word);
      if (keyValue && kind === 'plain' && this.keySeparatorAfter(end)) { kind = 'property'; }
      this.emit(end, kind);
      this.regexAllowed = word === 'return' || word === 'throw' || word === 'case' || word === 'typeof' ||
        word === 'void' || word === 'delete' || word === 'yield' || word === 'await';
      return;
    }
    const operator: boolean = '{}[]();:,.=+-*/%&|^!~<>?@#'.includes(character);
    if (javascript && (character === '+' || character === '-') && this.read(start + 1) === character) {
      // 后缀自增/自减后仍是除法上下文，不能把后续斜杠吞成未闭正则。
      this.emit(start + 2, 'plain'); return;
    }
    this.emit(start + 1, 'plain');
    // 高代理/非ASCII标识符不能切换为允许正则，避免中文变量后的除号吞掉行尾。
    this.regexAllowed = operator && character !== ')' && character !== ']' && character !== '}' && character !== '.';
  }

  private html(): void {
    const start: number = this.cursor;
    const character: string = this.read(start);
    if (!this.htmlTag) {
      if (this.matches(start, '<!--')) { this.emit(this.until(start + 4, '-->'), 'comment'); return; }
      if (this.matches(start, '<![CDATA[')) { this.emit(this.until(start + 9, ']]>'), 'plain'); return; }
      if (character === '<' && (letter(this.read(start + 1)) || '/!?'.includes(this.read(start + 1)) &&
        this.read(start + 1) !== '')) {
        let end: number = start + 1;
        if (this.read(end) === '/' || this.read(end) === '!' || this.read(end) === '?') { end++; }
        this.htmlTag = true; this.htmlName = true;
        this.emit(end, 'tag'); return;
      }
      // HTML文本中的数字/引号不能误当JS/JSON词法。
      this.emit(start + 1, 'plain'); return;
    }
    if (character === '"' || character === "'") {
      this.emit(this.quoted(start, character, true, false), 'string'); return;
    }
    if (character === '>') {
      this.htmlTag = false; this.htmlName = false; this.emit(start + 1, 'tag'); return;
    }
    if (wordStart(character) || character === '-') {
      const end: number = this.wordEnd(start, true);
      this.emit(end, this.htmlName ? 'tag' : 'property'); this.htmlName = false; return;
    }
    this.emit(start + 1, 'plain');
  }

  private css(): void {
    const start: number = this.cursor;
    const character: string = this.read(start);
    if (this.matches(start, '/*')) { this.emit(this.until(start + 2, '*/'), 'comment'); return; }
    if (character === '"' || character === "'") {
      this.emit(this.quoted(start, character, false, true), 'string'); return;
    }
    if (digit(character) || (character === '.' && digit(this.read(start + 1)))) {
      let end: number = this.numberEnd(start);
      while (letter(this.read(end)) || this.read(end) === '%') { end++; }
      this.emit(end, 'number'); return;
    }
    if (character === '#' && this.cssValue) {
      let end: number = start + 1;
      while (wordPart(this.read(end))) { end++; }
      this.emit(end, 'number'); return;
    }
    if (wordStart(character) || character === '-' || character === '@') {
      let end: number = start + 1;
      while (wordPart(this.read(end)) || this.read(end) === '-') { end++; }
      let after: number = end;
      while (space(this.read(after))) { after++; }
      const kind: MarkdownHighlightKind = character === '@' ? 'keyword' : this.cssDepth > 0 &&
        !this.cssValue && this.read(after) === ':' ? 'property' : 'plain';
      this.emit(end, kind); return;
    }
    if (character === '{') { this.cssDepth++; this.cssValue = false; }
    if (character === '}') { this.cssDepth = Math.max(0, this.cssDepth - 1); this.cssValue = false; }
    if (character === ';') { this.cssValue = false; }
    if (character === ':' && this.cssDepth > 0) { this.cssValue = true; }
    this.emit(start + 1, 'plain');
  }

  /** diff 行级分派（U4）：+++ / --- 文件头行先判（行首同样是 +/-，后判会被增删行吞掉），
   *  再 @@ hunk 头、再 +/- 增删行；同类行由 emit 同 kind 合并。 */
  private diffLine(): void {
    const start: number = this.cursor;
    const end: number = this.diffLineEnd(start);
    let kind: MarkdownHighlightKind = 'plain';
    if (this.matches(start, '+++') || this.matches(start, '---')) { kind = 'fileHeader'; }
    else if (this.matches(start, '@@')) { kind = 'hunk'; }
    else if (this.read(start) === '+') { kind = 'addition'; }
    else if (this.read(start) === '-') { kind = 'deletion'; }
    this.emit(end, kind);
  }

  /** 行尾连换行符整体返回（\r\n 计一对），空行（仅换行）也保一字符进展供 emit 前移。 */
  private diffLineEnd(start: number): number {
    let end: number = this.lineEnd(start);
    if (end < this.source.length) {
      if (this.read(end) === '\r') { end++; }
      if (this.read(end) === '\n') { end++; }
    }
    return end;
  }

  scan(): MarkdownHighlightRun[] {
    while (this.cursor < this.source.length) {
      if (this.language === 'html') { this.html(); }
      else if (this.language === 'css') { this.css(); }
      else if (this.language === 'diff') { this.diffLine(); }
      else { this.code(); }
    }
    for (const run of this.runs) { run.text = this.source.substring(run.start, run.end); }
    return this.runs;
  }
}

export function markdownHighlight(source: string, language: string): MarkdownHighlightResult {
  const normalized: string = languageOf(language);
  if (source === '') { return plainResult(source, normalized, 'plain', ''); }
  if (normalized === '' || normalized === 'plain') {
    return plainResult(source, normalized, 'plain', normalized === 'plain' ? '按纯源码显示' :
      '未指定或暂不支持此代码语言，按纯源码显示');
  }
  if (source.length > MARKDOWN_HIGHLIGHT_MAX_UNITS) {
    return plainResult(source, normalized, 'limited', '代码较长，已按纯源码显示。完整内容仍可阅读和复制');
  }
  const scanner: HighlightScanner = new HighlightScanner(source, normalized);
  try {
    return { runs: scanner.scan(), language: normalized, status: 'highlighted', message: '', readUnits: scanner.readUnits };
  } catch (failure) {
    return plainResult(source, normalized, scanner.limited ? 'limited' : 'failed', scanner.limited ?
      '高亮已达处理上限，已按纯源码显示。完整内容仍可阅读和复制' :
      '代码高亮失败，已保留完整源码', scanner.readUnits);
  }
}

/** 组件实例只保留当前内容。语义快照换壳但代码未变时复用，不累积历史、不持有AST。 */
export class MarkdownHighlightCache {
  private source: string = '';
  private language: string = '';
  private result: MarkdownHighlightResult | undefined = undefined;

  read(source: string, language: string): MarkdownHighlightResult {
    if (this.result !== undefined && this.source === source && this.language === language) { return this.result; }
    this.source = source;
    this.language = language;
    this.result = markdownHighlight(source, language);
    return this.result;
  }

  clear(): void { this.source = ''; this.language = ''; this.result = undefined; }
}
