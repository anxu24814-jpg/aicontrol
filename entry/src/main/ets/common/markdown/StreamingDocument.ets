/**
 * 保真原文、增量边界与按需语义解释的同步文档生命周期。无 ArkUI / Kit / Node 依赖。
 * append 只接受 delta，不做全文前缀比较；snapshot/sourceText/semanticSnapshot 是显式读取。
 *
 * 原文以 4096 UTF-16 单元为页。未满页按对齐的二进制片合并，最多 12 片，不持有逐字片
 * 历史、不逐片全文 +=；每单元在一页内最多参与 12 次合并，完整页从不因 append 重写，页
 * 数组扩容为摊销成本。入参逐 UTF-16 单元读出在有界片内 join，页不保存入参 substring——
 * 避免小页因 VM 的共享子串实现仍保留整个大入参的 backing string。
 */
import {
  MarkdownBlock,
  MarkdownDocumentSnapshot,
  MarkdownDocumentToken,
  MarkdownDocumentUpdate,
  MarkdownEndReason,
  MarkdownWorkCounter,
  MarkdownWorkMetrics
} from './MarkdownDocumentModel';
import { MarkdownBoundaryScanner } from './MarkdownBoundaryScanner';
import { MarkdownSemanticDocument } from './MarkdownSemanticDocument';
import { MarkdownSemanticSnapshot, MarkdownSemanticWork } from './MarkdownSemanticModel';

const SOURCE_PAGE_UNITS: number = 4096;

/** 源缓冲私有于本文档，不向调用方泄漏片数组。 */
class MarkdownSourceBuffer {
  private pages: string[] = [];
  private tailParts: string[] = [];
  private tailUnits: number = 0;
  private size: number = 0;
  private work: MarkdownWorkCounter;

  constructor(work: MarkdownWorkCounter) {
    this.work = work;
  }

  length(): number {
    return this.size;
  }

  append(delta: string): void {
    let offset: number = 0;
    while (offset < delta.length) {
      if (this.tailUnits === 0 && delta.length - offset >= SOURCE_PAGE_UNITS) {
        this.pages.push(this.copyOwnedFragment(delta, offset, SOURCE_PAGE_UNITS));
        this.work.sourceChunkVisits++;
        offset += SOURCE_PAGE_UNITS;
        this.size += SOURCE_PAGE_UNITS;
        continue;
      }
      const available: number = Math.min(delta.length - offset, SOURCE_PAGE_UNITS - this.tailUnits);
      let pieceLength: number = 1;
      while (pieceLength * 2 <= available && this.tailUnits % (pieceLength * 2) === 0) {
        pieceLength *= 2;
      }
      let piece: string = this.copyOwnedFragment(delta, offset, pieceLength);
      offset += pieceLength;
      this.tailUnits += pieceLength;
      this.size += pieceLength;
      while (this.tailParts.length > 0) {
        const previous: string = this.tailParts[this.tailParts.length - 1];
        this.work.sourceChunkVisits++;
        if (previous.length !== piece.length) {
          break;
        }
        this.tailParts.pop();
        piece = previous + piece;
        this.work.sourceCopiedUnits += piece.length;
      }
      if (this.tailUnits === SOURCE_PAGE_UNITS) {
        this.pages.push(piece);
        this.tailUnits = 0;
      } else {
        this.tailParts.push(piece);
      }
      this.work.sourceChunkVisits++;
    }
    this.updateHolding();
  }

  /** 尾修订允许复制一页之内的残片；不读保留的完整页前缀。 */
  truncate(from: number): void {
    const pageCount: number = Math.floor(from / SOURCE_PAGE_UNITS);
    const partialUnits: number = from % SOURCE_PAGE_UNITS;
    let partial: string = '';
    if (partialUnits > 0) {
      if (pageCount < this.pages.length) {
        this.work.sourceChunkVisits++;
        partial = this.pages[pageCount].substring(0, partialUnits);
        this.work.sourceCopiedUnits += partialUnits;
      } else {
        // 最多 12 个片、总长 < 一页；此物化专门计入源缓冲复制。
        const tail: string = this.tailParts.join('');
        this.work.sourceChunkVisits += this.tailParts.length;
        this.work.sourceCopiedUnits += this.tailUnits;
        partial = tail.substring(0, partialUnits);
        this.work.sourceCopiedUnits += partialUnits;
      }
    }
    this.work.sourceChunkVisits += this.pages.length - pageCount + this.tailParts.length;
    this.pages.length = pageCount;
    this.tailParts = [];
    this.tailUnits = 0;
    this.size = pageCount * SOURCE_PAGE_UNITS;
    this.append(partial);
  }

  scanFrom(from: number, scanner: MarkdownBoundaryScanner): void {
    let pageIndex: number = Math.floor(from / SOURCE_PAGE_UNITS);
    let localStart: number = from % SOURCE_PAGE_UNITS;
    while (pageIndex < this.pages.length) {
      const page: string = this.pages[pageIndex];
      this.work.sourceChunkVisits++;
      scanner.feed(page, localStart, page.length, true);
      localStart = 0;
      pageIndex++;
    }
    // 页下标直达起点；只在最后未满页的常数个片中定位，不遍历稳定源前缀。
    let tailOffset: number = 0;
    const tailFrom: number = Math.max(0, from - this.pages.length * SOURCE_PAGE_UNITS);
    for (let index: number = 0; index < this.tailParts.length; index++) {
      const part: string = this.tailParts[index];
      this.work.sourceChunkVisits++;
      if (tailOffset + part.length > tailFrom) {
        scanner.feed(part, Math.max(0, tailFrom - tailOffset), part.length, true);
      }
      tailOffset += part.length;
    }
  }

  text(): string {
    const parts: string[] = [];
    for (let index: number = 0; index < this.pages.length; index++) {
      parts.push(this.pages[index]);
      this.work.sourceChunkVisits++;
    }
    for (let index: number = 0; index < this.tailParts.length; index++) {
      parts.push(this.tailParts[index]);
      this.work.sourceChunkVisits++;
    }
    this.work.materializedUnits += this.size;
    return parts.join('');
  }

  readRange(start: number, end: number): string {
    const pieces: string[] = [];
    let pageIndex: number = Math.floor(start / SOURCE_PAGE_UNITS);
    while (pageIndex < this.pages.length && pageIndex * SOURCE_PAGE_UNITS < end) {
      const pageStart: number = pageIndex * SOURCE_PAGE_UNITS;
      const piece: string = this.pages[pageIndex].substring(Math.max(0, start - pageStart),
        Math.min(SOURCE_PAGE_UNITS, end - pageStart));
      pieces.push(piece);
      this.work.sourceChunkVisits++;
      this.work.materializedUnits += piece.length;
      pageIndex++;
    }
    let tailStart: number = this.pages.length * SOURCE_PAGE_UNITS;
    for (let index: number = 0; index < this.tailParts.length && tailStart < end; index++) {
      const part: string = this.tailParts[index];
      this.work.sourceChunkVisits++;
      if (tailStart + part.length > start) {
        const piece: string = part.substring(Math.max(0, start - tailStart), Math.min(part.length, end - tailStart));
        pieces.push(piece);
        this.work.materializedUnits += piece.length;
      }
      tailStart += part.length;
    }
    this.work.materializedUnits += end - start;
    return pieces.join('');
  }

  clear(): void {
    this.work.sourceChunkVisits += this.pages.length + this.tailParts.length;
    this.pages = [];
    this.tailParts = [];
    this.tailUnits = 0;
    this.size = 0;
    this.updateHolding();
  }

  /** 所有调用点保证 1 <= units <= 一页；charAt 不解码/配对孤立代理单元。 */
  private copyOwnedFragment(text: string, start: number, units: number): string {
    if (units === 1) {
      this.work.sourceReadUnits++;
      this.work.sourceCopiedUnits++;
      return text.charAt(start);
    }
    const characters: string[] = [];
    for (let index: number = start; index < start + units; index++) {
      characters.push(text.charAt(index));
      this.work.sourceReadUnits++;
      this.work.sourceCopiedUnits++;
    }
    this.work.sourceCopiedUnits += units;
    return characters.join('');
  }

  private updateHolding(): void {
    this.work.retainedSourceChunks = this.pages.length + this.tailParts.length;
  }
}

export class StreamingDocument {
  private documentId: string;
  private generation: number = 0;
  private revision: number = 0;
  private endReason: MarkdownEndReason | undefined = undefined;
  private disposed: boolean = false;
  private work: MarkdownWorkCounter = new MarkdownWorkCounter();
  private source: MarkdownSourceBuffer;
  private scanner: MarkdownBoundaryScanner;
  private semantic: MarkdownSemanticDocument = new MarkdownSemanticDocument();

  constructor(documentId: string) {
    this.requireIdentity(documentId);
    this.documentId = documentId;
    this.source = new MarkdownSourceBuffer(this.work);
    this.scanner = new MarkdownBoundaryScanner(this.work);
  }

  append(delta: string): MarkdownDocumentUpdate {
    this.requireInput();
    this.scanner.beginUpdate();
    if (delta.length > 0) {
      this.requireRevisionCapacity();
      this.semantic.changed(this.source.length());
      this.source.append(delta);
      this.scanner.feed(delta);
      this.revision++;
    }
    return this.update();
  }

  replace(source: string): MarkdownDocumentUpdate {
    return this.reset(this.documentId, source);
  }

  reset(documentId: string, initial: string = ''): MarkdownDocumentUpdate {
    this.requireAlive();
    this.requireIdentity(documentId);
    if (this.generation >= Number.MAX_SAFE_INTEGER) {
      throw new Error('Markdown 文档世代已达安全整数上限');
    }
    this.generation++;
    this.revision = 0;
    this.documentId = documentId;
    this.endReason = undefined;
    this.source.clear();
    this.scanner.clear();
    this.semantic.clear();
    this.source.append(initial);
    this.scanner.feed(initial);
    return this.update();
  }

  reviseTail(from: number, replacement: string): MarkdownDocumentUpdate {
    this.requireInput();
    if (!Number.isInteger(from) || from < this.scanner.stableUntil() || from > this.source.length()) {
      throw new Error('Markdown 尾修订位置须为稳定边界至原文末尾内的整数');
    }
    this.requireRevisionCapacity();
    const restart: number = this.scanner.stableUntil();
    this.scanner.beginUpdate();
    this.semantic.revise(from);
    this.source.truncate(from);
    this.source.append(replacement);
    this.scanner.rewindToStable();
    this.source.scanFrom(restart, this.scanner);
    this.revision++;
    return this.update();
  }

  finish(reason: MarkdownEndReason): MarkdownDocumentUpdate {
    this.requireAlive();
    if (reason !== 'done' && reason !== 'stopped' && reason !== 'failed' && reason !== 'truncated') {
      throw new Error('Markdown 输入结束原因无效');
    }
    if (this.endReason !== undefined && this.endReason !== reason) {
      throw new Error('Markdown 输入已使用不同原因结束');
    }
    this.scanner.beginUpdate();
    if (this.endReason === undefined) {
      this.requireRevisionCapacity();
      this.scanner.finish();
      this.endReason = reason;
      this.revision++;
    }
    return this.update();
  }

  token(): MarkdownDocumentToken {
    return { documentId: this.documentId, generation: this.generation, revision: this.revision };
  }

  accepts(token: MarkdownDocumentToken): boolean {
    return !this.disposed && token.documentId === this.documentId &&
      token.generation === this.generation && token.revision === this.revision;
  }

  sourceText(): string {
    this.requireAlive();
    return this.source.text();
  }

  snapshot(): MarkdownDocumentSnapshot {
    this.requireAlive();
    return {
      token: this.token(),
      blocks: this.scanner.copyBlocks(0),
      stableUntil: this.scanner.stableUntil(),
      sourceLength: this.source.length(),
      endReason: this.endReason
    };
  }

  semanticSnapshot(): MarkdownSemanticSnapshot {
    this.requireAlive();
    return this.semantic.snapshot(this.token(), this.source.length(), this.endReason,
      (start: number, end: number): string => this.source.readRange(start, end));
  }

  semanticMetrics(): MarkdownSemanticWork {
    return this.semantic.metrics();
  }

  metrics(): MarkdownWorkMetrics {
    return {
      scannedUnits: this.work.scannedUnits,
      reparsedUnits: this.work.reparsedUnits,
      sourceReadUnits: this.work.sourceReadUnits,
      sourceCopiedUnits: this.work.sourceCopiedUnits,
      materializedUnits: this.work.materializedUnits,
      nodeVisits: this.work.nodeVisits,
      nodeCopies: this.work.nodeCopies,
      sourceChunkVisits: this.work.sourceChunkVisits,
      retainedSourceChunks: this.work.retainedSourceChunks,
      retainedCheckpoints: this.work.retainedCheckpoints
    };
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.source.clear();
    this.scanner.clear();
    this.semantic.clear();
  }

  private update(): MarkdownDocumentUpdate {
    const retained: number = this.scanner.retainedBlockCount();
    const blocks: MarkdownBlock[] = this.scanner.copyBlocks(retained);
    return {
      token: this.token(),
      retainedBlockCount: retained,
      blocks: blocks,
      stableUntil: this.scanner.stableUntil(),
      sourceLength: this.source.length(),
      endReason: this.endReason
    };
  }

  private requireAlive(): void {
    if (this.disposed) {
      throw new Error('Markdown 文档已销毁');
    }
  }

  private requireInput(): void {
    this.requireAlive();
    if (this.endReason !== undefined) {
      throw new Error('Markdown 文档输入已结束');
    }
  }

  private requireIdentity(documentId: string): void {
    if (documentId.length === 0) {
      throw new Error('Markdown 文档身份不能为空');
    }
  }

  private requireRevisionCapacity(): void {
    if (this.revision >= Number.MAX_SAFE_INTEGER) {
      throw new Error('Markdown 文档修订已达安全整数上限');
    }
  }
}
