/**
 * 顶层 raw / 单行 blank / fence 的增量边界扫描器：只读新到达的 UTF-16 单元，当前行只保
 * DFA 标量与行前最后一块的 checkpoint（不保存行文本或逐行历史），长 info、尾空白、未闭
 * 大围栏不会每片回扫。
 * 未决行的展示可重分类：开栏 info 中后来出现反引号、闭栏后来出现非空白时，从同一
 * checkpoint 重投影至多两块，而不是撤回/重扫字符。
 * 扫描位置与 stableUntil 分离：raw 需要后继分隔事实，开放 fence 前的 raw 也不能先冻结，
 * 仅完整 blank / 实际闭 fence 可封存其前缀；活跃输入不在裸 CR 后封存，以免 reviseTail
 * 插入 LF 重新配对改变前缀范围。
 */
import {
  MarkdownBlock,
  MarkdownBlockKind,
  MarkdownWorkCounter,
  copyMarkdownBlock
} from './MarkdownDocumentModel';

type FenceLineStage = 'indent' | 'run' | 'rest' | 'invalid';

export class MarkdownBoundaryScanner {
  private work: MarkdownWorkCounter;
  private blocks: MarkdownBlock[] = [];
  private nextId: number = 1;
  private position: number = 0;
  private stableOffset: number = 0;
  private stableCount: number = 0;
  private changedFrom: number = 0;
  private pendingCr: boolean = false;

  // 当前行 checkpoint。行前整片前缀不复制，最多保一份最后块的值。
  private lineActive: boolean = false;
  private lineStart: number = 0;
  private lineBlockCount: number = 0;
  private lineBase: MarkdownBlock | undefined = undefined;
  private lineId: number = 0;
  private lineBlank: boolean = true;
  private leadingSpaces: number = 0;
  private fenceStage: FenceLineStage = 'indent';
  private fenceCharacter: string = '';
  private fenceLength: number = 0;
  private infoHasBacktick: boolean = false;
  private restIsWhitespace: boolean = true;

  constructor(work: MarkdownWorkCounter) {
    this.work = work;
  }

  beginUpdate(): void {
    this.changedFrom = this.blocks.length;
  }

  retainedBlockCount(): number {
    return this.changedFrom;
  }

  stableUntil(): number {
    return this.stableOffset;
  }

  blockCount(): number {
    return this.blocks.length;
  }

  copyBlocks(from: number): MarkdownBlock[] {
    const result: MarkdownBlock[] = [];
    for (let index: number = from; index < this.blocks.length; index++) {
      result.push(copyMarkdownBlock(this.blocks[index], this.work));
    }
    return result;
  }

  /** 源页恢复也走同一 DFA；start/end 是 text 内索引，不另切长子串。 */
  feed(text: string, start: number = 0, end: number = text.length, reparsing: boolean = false): void {
    for (let index: number = start; index < end; index++) {
      const code: number = text.charCodeAt(index);
      this.work.scannedUnits++;
      if (reparsing) {
        this.work.reparsedUnits++;
      }
      if (this.pendingCr) {
        this.pendingCr = false;
        if (code === 10) {
          this.position++;
          this.commitLine(true);
          continue;
        }
        // 非 LF 证明上一 CR 独立成行，但该 CR 后仍不是尾修订的安全端点。
        this.commitLine(false);
      }
      if (!this.lineActive) {
        this.beginLine();
      }
      this.position++;
      if (code === 13) {
        this.pendingCr = true;
      } else if (code === 10) {
        this.commitLine(true);
      } else {
        this.scanContent(code);
      }
    }
    if (this.lineActive) {
      this.projectLine();
    }
  }

  finish(): void {
    if (this.lineActive) {
      this.pendingCr = false;
      this.commitLine(false);
    }
    // 输入已结束，不再允许 reviseTail，最后一块也成为完整结构前缀。
    this.stableOffset = this.position;
    this.stableCount = this.blocks.length;
  }

  /** stableOffset 在行边界，且前缀最后块不会与重扫的新 raw 合并。 */
  rewindToStable(): void {
    this.dropBlocks(this.stableCount);
    this.changedFrom = Math.min(this.changedFrom, this.stableCount);
    this.position = this.stableOffset;
    this.clearLine();
    this.pendingCr = false;
  }

  clear(): void {
    this.dropBlocks(0);
    this.changedFrom = 0;
    this.position = 0;
    this.stableOffset = 0;
    this.stableCount = 0;
    this.clearLine();
    this.pendingCr = false;
    // 节点序号属于实例，不因 reset / replace / dispose 回收。
  }

  private beginLine(): void {
    this.lineActive = true;
    this.work.retainedCheckpoints = 1;
    this.lineStart = this.position;
    this.lineBlockCount = this.blocks.length;
    if (this.lineBlockCount > 0) {
      this.lineBase = copyMarkdownBlock(this.blocks[this.lineBlockCount - 1], this.work);
    }
  }

  private clearLine(): void {
    this.lineActive = false;
    this.work.retainedCheckpoints = 0;
    this.lineBase = undefined;
    this.lineId = 0;
    this.lineBlank = true;
    this.leadingSpaces = 0;
    this.fenceStage = 'indent';
    this.fenceCharacter = '';
    this.fenceLength = 0;
    this.infoHasBacktick = false;
    this.restIsWhitespace = true;
  }

  private scanContent(code: number): void {
    const whitespace: boolean = code === 32 || code === 9;
    if (!whitespace) {
      this.lineBlank = false;
    }
    if (this.fenceStage === 'invalid') {
      return;
    }
    if (this.fenceStage === 'indent') {
      if (code === 32) {
        this.leadingSpaces++;
        if (this.leadingSpaces > 3) {
          this.fenceStage = 'invalid';
        }
      } else if (code === 96 || code === 126) {
        this.fenceStage = 'run';
        this.fenceCharacter = code === 96 ? '`' : '~';
        this.fenceLength = 1;
      } else {
        this.fenceStage = 'invalid';
      }
      return;
    }
    if (this.fenceStage === 'run') {
      const sameCharacter: boolean = (code === 96 && this.fenceCharacter === '`') ||
        (code === 126 && this.fenceCharacter === '~');
      if (sameCharacter) {
        this.fenceLength++;
        return;
      }
      this.fenceStage = 'rest';
    }
    if (code === 96) {
      this.infoHasBacktick = true;
    }
    if (!whitespace) {
      this.restIsWhitespace = false;
    }
  }

  private isOpeningFence(): boolean {
    return this.fenceStage !== 'invalid' && this.fenceLength >= 3 &&
      (this.fenceCharacter !== '`' || !this.infoHasBacktick);
  }

  private isClosingFence(base: MarkdownBlock): boolean {
    this.work.nodeVisits++;
    return this.fenceStage !== 'invalid' && this.fenceCharacter === base.fenceCharacter &&
      this.fenceLength >= base.fenceLength && this.restIsWhitespace;
  }

  private currentLineId(): number {
    if (this.lineId === 0) {
      if (this.nextId >= Number.MAX_SAFE_INTEGER) {
        throw new Error('Markdown 节点序号已达安全整数上限');
      }
      this.lineId = this.nextId;
      this.nextId++;
    }
    return this.lineId;
  }

  private projectLine(): void {
    const base: MarkdownBlock | undefined = this.lineBase;
    if (base !== undefined) {
      this.work.nodeVisits++;
      if (base.kind === 'fence' && !base.closed) {
        this.writeBlock(this.lineBlockCount - 1, base.id, 'fence', base.range.start,
          this.position, this.isClosingFence(base), base.fenceCharacter, base.fenceLength);
        this.dropBlocks(this.lineBlockCount);
        return;
      }
    }
    const kind: MarkdownBlockKind = this.lineBlank ? 'blank' : (this.isOpeningFence() ? 'fence' : 'raw');
    if (base !== undefined) {
      this.work.nodeVisits++;
      if (kind === 'raw' && base.kind === 'raw') {
        this.writeBlock(this.lineBlockCount - 1, base.id, 'raw', base.range.start, this.position, false, '', 0);
        this.dropBlocks(this.lineBlockCount);
        return;
      }
      // 临时 raw 曾合入前块，后来成为 fence/blank 时恢复行前端点。
      this.writeBlock(this.lineBlockCount - 1, base.id, base.kind, base.range.start,
        base.range.end, base.closed, base.fenceCharacter, base.fenceLength);
    }
    this.writeBlock(this.lineBlockCount, this.currentLineId(), kind, this.lineStart,
      this.position, false, kind === 'fence' ? this.fenceCharacter : '',
      kind === 'fence' ? this.fenceLength : 0);
    this.dropBlocks(this.lineBlockCount + 1);
  }

  private commitLine(safeLineEnding: boolean): void {
    this.projectLine();
    const last: MarkdownBlock = this.blocks[this.blocks.length - 1];
    this.work.nodeVisits++;
    if (safeLineEnding && (last.kind === 'blank' || (last.kind === 'fence' && last.closed))) {
      this.stableOffset = this.position;
      this.stableCount = this.blocks.length;
    }
    this.clearLine();
  }

  private writeBlock(index: number, id: number, kind: MarkdownBlockKind, start: number,
    end: number, closed: boolean, fenceCharacter: string, fenceLength: number): void {
    if (index < this.blocks.length) {
      const existing: MarkdownBlock = this.blocks[index];
      this.work.nodeVisits++;
      if (existing.id === id && existing.kind === kind && existing.range.start === start &&
        existing.range.end === end && existing.closed === closed &&
        existing.fenceCharacter === fenceCharacter && existing.fenceLength === fenceLength) {
        return;
      }
      existing.id = id;
      existing.kind = kind;
      existing.range.start = start;
      existing.range.end = end;
      existing.closed = closed;
      existing.fenceCharacter = fenceCharacter;
      existing.fenceLength = fenceLength;
    } else {
      const block: MarkdownBlock = {
        id: id,
        kind: kind,
        range: { start: start, end: end },
        closed: closed,
        fenceCharacter: fenceCharacter,
        fenceLength: fenceLength
      };
      this.blocks.push(block);
    }
    this.changedFrom = Math.min(this.changedFrom, index);
  }

  private dropBlocks(count: number): void {
    while (this.blocks.length > count) {
      this.blocks.pop();
      this.work.nodeVisits++;
      this.changedFrom = Math.min(this.changedFrom, this.blocks.length);
    }
  }
}
