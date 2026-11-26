// 工作区编辑纯函数域：workspace_edit 的匹配器族（三级级联 exact → line_trimmed →
// block_anchor + reindent）+ 策略常量 + 成功回执与 E9/E10/E13 文案组装。
// · 匹配算法蓝本 = RikkaHub TextReplacers.kt（RIK）逐条照抄——Kotlin→ArkTS 移植对齐点：
//   ① String.lines() ≡ JS split('\n')（reindent 生效路径按「CRLF 归一为 LF」逐字实现；
//   仅 old_text 自身含孤立 \r 的病态输入下窗口划分与 RIK 不同，read 回执不产该形态）；
//   ② 窗口 subList 偏移整数边界照抄；③ UTF-16 码元切分（substring 语义天然对齐 Kotlin）。
// · 依赖纪律：import 白名单 = WorkspaceUtil.formatWorkspaceSize + WorkspaceReply.
//   workspaceOverwriteNote 恰两值——E13 的 1MB 常量经参数传入不破白名单；零 kit、零 store。
//   断言直跑 = 复制本件为 .tmp 副本（interface 导入行剥除 + 值导入改指 .tmp 副本）。
// · 消费方：store 编排 WorkspaceDbEdit.ets（匹配与回执组装）+ ToolWorkspace.ets（E7/E8
//   前置参数闸）。
// · 不并入 WorkspaceSearchUtil（反碎片下限②）：检索 = 「找文件/找行」，编辑 = 「改内容」，
//   职责缝不同，并入即混域。
import { formatWorkspaceSize } from './WorkspaceUtil';
import { workspaceOverwriteNote } from './WorkspaceReply';

// ── 策略常量（内部判别位；回执措辞统一「空白宽容匹配」，策略名不散写回执）──
export const WORKSPACE_EDIT_STRATEGY_EXACT: string = 'exact';
export const WORKSPACE_EDIT_STRATEGY_LINE_TRIMMED: string = 'line_trimmed';
export const WORKSPACE_EDIT_STRATEGY_BLOCK_ANCHOR: string = 'block_anchor';

// 匹配区间（UTF-16 码元偏移；endExclusive 吞末行行尾空白、不含换行符——RIK :124）
interface WorkspaceEditMatch {
  start: number;
  endExclusive: number;
  replacement: string;
}

// 匹配结果四态：'ok' 成功 / 'ambiguous' 级命中且多匹配未开 replace_all / 'not_found' 级联
// 全空 / 'empty' old_string 空串（防御位——E7 在执行器前置闸，正常链路不达）
export interface WorkspaceTextReplaceResult {
  status: string;
  updated: string;
  replacements: number;
  occurrences: number;
  strategy: string;
}

// 替换器契约（RIK TextReplacer 同构）
interface WorkspaceTextReplacer {
  name: string;
  findMatches(content: string, oldText: string, newText: string): WorkspaceEditMatch[];
}

// ── 第一级 exact：精确匹配，非重叠推进计数（与 String.replace 语义一致——'aaa' 里 'aa'
//    记 1 处；RIK :78-89）──
class ExactReplacer implements WorkspaceTextReplacer {
  name: string = WORKSPACE_EDIT_STRATEGY_EXACT;

  findMatches(content: string, oldText: string, newText: string): WorkspaceEditMatch[] {
    const matches: WorkspaceEditMatch[] = [];
    let index: number = content.indexOf(oldText);
    while (index >= 0) {
      matches.push({ start: index, endExclusive: index + oldText.length,
        replacement: newText });
      index = content.indexOf(oldText, index + oldText.length);
    }
    return matches;
  }
}

// 内容行切分（RIK 照抄）：'\n' 切行、行尾 '\r' 归入行界不进文本（endExclusive 回退一格吞
// \r）、保留原始偏移；末段（含空尾段）照录
interface WorkspaceEditLineOffset {
  start: number;
  endExclusive: number;
  text: string;
}

function splitLinesWithOffsets(content: string): WorkspaceEditLineOffset[] {
  const lines: WorkspaceEditLineOffset[] = [];
  let start: number = 0;
  for (let index = 0; index < content.length; index++) {
    if (content[index] === '\n') {
      const end: number = index > start && content[index - 1] === '\r' ? index - 1 : index;
      lines.push({ start: start, endExclusive: end, text: content.substring(start, end) });
      start = index + 1;
    }
  }
  lines.push({ start: start, endExclusive: content.length, text: content.substring(start) });
  return lines;
}

// 行首缩进（空格与制表符前缀，RIK indentOf）
function indentOf(line: string): string {
  let n: number = 0;
  while (n < line.length && (line[n] === ' ' || line[n] === '\t')) {
    n++;
  }
  return line.substring(0, n);
}

// 行切分按 Kotlin lines() 语义（CR / CRLF / LF 都切行——reindent 专用；普通路径用 split('\n')）
function kotlinLines(text: string): string[] {
  return text.split(/\r\n|\n|\r/);
}

// 重排缩进（RIK 照抄）：以窗口首行真实缩进为新基准，仅对以 oldIndent 开头且非空白的行重排；
// oldIndent == newIndent 原样返回（CRLF 保留）；生效时插入文本 CR/CRLF 归一为 LF
//（Kotlin lines() 切 CR 后 join('\n') 的天然行为，kotlinLines 显式对齐——RIK 同款非本仓新规）
function reindent(text: string, oldIndent: string, newIndent: string): string {
  if (oldIndent === newIndent) {
    return text;
  }
  return kotlinLines(text).map((line: string): string => {
    if (line.trim() === '') {
      return line;
    }
    if (line.startsWith(oldIndent)) {
      return newIndent + line.substring(oldIndent.length);
    }
    return line;
  }).join('\n');
}

// 去一个尾换行（\r\n 去 2、\n 去 1、无则原样）
function removeOneTrailingNewline(text: string): string {
  if (text.endsWith('\r\n')) {
    return text.substring(0, text.length - 2);
  }
  if (text.endsWith('\n')) {
    return text.substring(0, text.length - 1);
  }
  return text;
}

// ── 行级窗口匹配骨架（RIK 照抄）：old 与内容均按行拆、滑动比较窗口，命中后以匹配处首行
//    真实缩进重排 new_text ──
abstract class LineWindowReplacer implements WorkspaceTextReplacer {
  readonly name: string;

  constructor(name: string) {
    this.name = name;
  }

  // 窗口判据（逐行 trim 后比较的形态由子级定：整窗相等 / 首尾锚）
  protected abstract windowMatches(windowTrimmed: string[], oldTrimmed: string[]): boolean;

  // 适用性（缺省 = old 全为空白行时禁用宽松匹配，避免命中任意空白区域）
  protected isApplicable(oldTrimmed: string[]): boolean {
    for (const line of oldTrimmed) {
      if (line !== '') {
        return true;
      }
    }
    return false;
  }

  findMatches(content: string, oldText: string, newText: string): WorkspaceEditMatch[] {
    const rawOldLines: string[] = oldText.split('\n');
    // "foo\n" 语义上是一行：去掉空尾行，new_text 同步处理保持对称
    const dropTrailingEmpty: boolean = rawOldLines.length > 1 &&
      rawOldLines[rawOldLines.length - 1] === '';
    const oldLines: string[] = dropTrailingEmpty ? rawOldLines.slice(0, -1) : rawOldLines;
    const oldTrimmed: string[] = oldLines.map((line: string): string => line.trim());
    if (!this.isApplicable(oldTrimmed)) {
      return [];
    }
    const adjustedNewText: string = dropTrailingEmpty ?
      removeOneTrailingNewline(newText) : newText;
    const contentLines: WorkspaceEditLineOffset[] = splitLinesWithOffsets(content);
    const matches: WorkspaceEditMatch[] = [];
    let index: number = 0;
    while (index + oldLines.length <= contentLines.length) {
      const window: WorkspaceEditLineOffset[] =
        contentLines.slice(index, index + oldLines.length);
      if (this.windowMatches(window.map((l: WorkspaceEditLineOffset): string => l.text.trim()),
        oldTrimmed)) {
        const replacement: string = reindent(adjustedNewText,
          indentOf(oldLines[0]), indentOf(window[0].text));
        matches.push({ start: window[0].start, endExclusive: window[window.length - 1].endExclusive,
          replacement: replacement });
        index += oldLines.length;
      } else {
        index++;
      }
    }
    return matches;
  }
}

// ── 第二级 line_trimmed：逐行 trim 后整窗相等，容忍缩进/行尾空白/CRLF 差异 ──
class LineTrimmedReplacer extends LineWindowReplacer {
  constructor() {
    super(WORKSPACE_EDIT_STRATEGY_LINE_TRIMMED);
  }

  protected windowMatches(windowTrimmed: string[], oldTrimmed: string[]): boolean {
    if (windowTrimmed.length !== oldTrimmed.length) {
      return false;
    }
    for (let i = 0; i < windowTrimmed.length; i++) {
      if (windowTrimmed[i] !== oldTrimmed[i]) {
        return false;
      }
    }
    return true;
  }
}

// ── 第三级 block_anchor：old 至少 3 行且首尾行非空才适用；窗口首/尾行 trim 相等即命中、
//    中间行不比较、窗口行数仍须相等 ──
class BlockAnchorReplacer extends LineWindowReplacer {
  constructor() {
    super(WORKSPACE_EDIT_STRATEGY_BLOCK_ANCHOR);
  }

  protected isApplicable(oldTrimmed: string[]): boolean {
    return oldTrimmed.length >= 3 && oldTrimmed[0] !== '' &&
      oldTrimmed[oldTrimmed.length - 1] !== '';
  }

  protected windowMatches(windowTrimmed: string[], oldTrimmed: string[]): boolean {
    return windowTrimmed[0] === oldTrimmed[0] &&
      windowTrimmed[windowTrimmed.length - 1] === oldTrimmed[oldTrimmed.length - 1];
  }
}

// 级联顺序（RIK 同款）：取第一个有命中的级；某级命中即定案——多匹配直接报错、不降级继续
const WORKSPACE_EDIT_REPLACERS: WorkspaceTextReplacer[] = [new ExactReplacer(),
  new LineTrimmedReplacer(), new BlockAnchorReplacer()];

// 级联替换主口（RIK 照抄；throw 语义改判 status 四态——异常面收窄进结果对象，文案组装归
// 调用方）：replaceAll=false 要求文件内唯一命中
export function replaceWorkspaceText(content: string, oldText: string, newText: string,
  replaceAll: boolean): WorkspaceTextReplaceResult {
  if (oldText === '') {
    return { status: 'empty', updated: content, replacements: 0, occurrences: 0, strategy: '' };
  }
  for (const replacer of WORKSPACE_EDIT_REPLACERS) {
    const matches: WorkspaceEditMatch[] = replacer.findMatches(content, oldText, newText);
    if (matches.length === 0) {
      continue;
    }
    if (!replaceAll && matches.length > 1) {
      return { status: 'ambiguous', updated: content, replacements: 0,
        occurrences: matches.length, strategy: replacer.name };
    }
    const applied: WorkspaceEditMatch[] = replaceAll ?
      matches.slice().sort((a: WorkspaceEditMatch, b: WorkspaceEditMatch): number => a.start - b.start) :
      [matches.reduce((min: WorkspaceEditMatch, m: WorkspaceEditMatch): WorkspaceEditMatch =>
        m.start < min.start ? m : min)];
    let updated: string = '';
    let cursor: number = 0;
    for (const match of applied) {
      updated += content.substring(cursor, match.start) + match.replacement;
      cursor = match.endExclusive;
    }
    updated += content.substring(cursor);
    return { status: 'ok', updated: updated, replacements: applied.length,
      occurrences: matches.length, strategy: replacer.name };
  }
  return { status: 'not_found', updated: content, replacements: 0, occurrences: 0, strategy: '' };
}

// ── 行数口径（与 workspace_read 回执行号同源 = split('\n') 计数——A/B 前后值与 read 的
// 「共 N 行」一致，模型两侧对得上账）──
export function workspaceEditLineCount(content: string): number {
  return content.split('\n').length;
}

// ── E13 折中大小闸：编辑后字节数须 ≤ max(writeMaxBytes, 原文件 size)——大文件小幅编辑
//    不被 1MB 误拦。writeMaxBytes 由调用方传 WORKSPACE_WRITE_MAX_BYTES（import 白名单钉
//    两值，常量经参传入）──
export function workspaceEditSizeGateReason(newSizeBytes: number, originalSizeBytes: number,
  writeMaxBytes: number): string {
  const limit: number = Math.max(writeMaxBytes, originalSizeBytes);
  if (newSizeBytes > limit) {
    return '编辑后的文件超过 ' + formatWorkspaceSize(limit) +
      ' 的上限，无法保存。请调整替换内容后重试。';
  }
  return '';
}

// ── 成功回执组装：exact 级「替换 N 处」/ 宽容级「按空白宽容匹配替换 N 处」两态；A/B =
//    编辑前后全文行数；覆盖注记命中即末尾直拼（单源句）──
export function composeWorkspaceEditReply(name: string, strategy: string, replacements: number,
  beforeLineCount: number, afterLineCount: number, sizeBytes: number,
  overwriteKind: string): string {
  const base: string = (strategy === WORKSPACE_EDIT_STRATEGY_EXACT ?
    '已编辑「' + name + '」，替换 ' + replacements + ' 处，行数 ' :
    '已编辑「' + name + '」，按空白宽容匹配替换 ' + replacements + ' 处，行数 ') +
    beforeLineCount + '→' + afterLineCount + '，共 ' + sizeBytes + ' 字节。';
  const note: string = workspaceOverwriteNote(overwriteKind);
  return note === '' ? base : base + note;
}

// E9 零匹配文案（级联全空——提示重读与原样复制）
export function workspaceEditNotFoundText(name: string): string {
  return '在「' + name + '」里没有找到要替换的原文。请先用 workspace_read 重新读取该文件，' +
    '把 old_string 从读取结果里原样复制。';
}

// E10 多命中文案（唯一性失败——指引带前后文或 replace_all）
export function workspaceEditAmbiguousText(name: string): string {
  return '「' + name + '」里有多处内容与 old_string 相同，无法确定改哪一处。' +
    '请多带一些前后文让它唯一，或把 replace_all 设为 true 全部替换。';
}
