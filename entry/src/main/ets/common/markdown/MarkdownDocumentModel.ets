/**
 * 阶段 1 的保真源范围模型，不是完整 Markdown AST。
 * 偏移为 UTF-16 code unit 的半开区间。对象跨公共接口时逐字段复制，
 * readonly 并非运行期隔离保证，因此不把内部块、range 或 token 直接返回。
 */
export type MarkdownBlockKind = 'raw' | 'blank' | 'fence';
export type MarkdownEndReason = 'done' | 'stopped' | 'failed' | 'truncated';

let bindingSerial: number = 0;

/** 仅铸造身份序号，不持有消息或文档；不随组件/页面回收而复用。 */
export function nextMarkdownBindingId(): string {
  if (bindingSerial >= Number.MAX_SAFE_INTEGER) {
    throw new Error('Markdown 正文身份已达安全整数上限');
  }
  bindingSerial++;
  return 'markdown-body-' + bindingSerial;
}

export interface MarkdownDocumentToken {
  documentId: string;
  generation: number;
  revision: number;
}

export interface MarkdownSourceRange {
  start: number;
  end: number;
}

export interface MarkdownBlock {
  id: number;
  kind: MarkdownBlockKind;
  range: MarkdownSourceRange;
  closed: boolean;
  fenceCharacter: string;
  fenceLength: number;
}

export interface MarkdownDocumentUpdate {
  token: MarkdownDocumentToken;
  retainedBlockCount: number;
  blocks: MarkdownBlock[];
  stableUntil: number;
  sourceLength: number;
  endReason: MarkdownEndReason | undefined;
}

export interface MarkdownDocumentSnapshot {
  token: MarkdownDocumentToken;
  blocks: MarkdownBlock[];
  stableUntil: number;
  sourceLength: number;
  endReason: MarkdownEndReason | undefined;
}

/**
 * 累计量在 reset/replace 后不清零，各量不相加冒称 CPU 指令数。
 * scannedUnits：DFA 实际读取的 UTF-16 单元（每次 charCodeAt 计一）；reparsedUnits：其中
 * reviseTail 恢复扫描所读，是 scannedUnits 的子集。
 * sourceReadUnits：源缓冲独立复制入口的 charAt 读取量，与 DFA 的 scannedUnits 分开计量，
 * 不把源读取冒称语法扫描。
 * sourceCopiedUnits：独立复制的 charAt/join 输出、已有自有页的 substring、页内串接输出，
 * 按逻辑复制量记账（VM 可能共享子串/使用 rope 也不记零）；不含 sourceText 的物化。
 * materializedUnits：sourceText 及显式尾区读取时 substring/join 输出的单元数。
 * nodeVisits：取内部块记录、复制/移除一个块的访问数（含 snapshot）；nodeCopies：行
 * checkpoint 或公共返回值的块记录副本数（含 range）。
 * sourceChunkVisits：源页/页内片的索引、搬运与释放槽位，不含 VM 容器扩容和实际 GC；
 * clear/reset/dispose 按放弃的槽位数记账。
 * retainedSourceChunks：当前完整页数 + 未满页的合并片数，不含调用方返回值；
 * retainedCheckpoints：当前持有的行 checkpoint 数（0 或 1，不随行数累积）。
 */
export interface MarkdownWorkMetrics {
  scannedUnits: number;
  reparsedUnits: number;
  sourceReadUnits: number;
  sourceCopiedUnits: number;
  materializedUnits: number;
  nodeVisits: number;
  nodeCopies: number;
  sourceChunkVisits: number;
  retainedSourceChunks: number;
  retainedCheckpoints: number;
}

// 内部计量器。公共 metrics() 必须另建值对象，不能返回本实例。
export class MarkdownWorkCounter implements MarkdownWorkMetrics {
  scannedUnits: number = 0;
  reparsedUnits: number = 0;
  sourceReadUnits: number = 0;
  sourceCopiedUnits: number = 0;
  materializedUnits: number = 0;
  nodeVisits: number = 0;
  nodeCopies: number = 0;
  sourceChunkVisits: number = 0;
  retainedSourceChunks: number = 0;
  retainedCheckpoints: number = 0;
}

export function copyMarkdownBlock(block: MarkdownBlock, work: MarkdownWorkCounter): MarkdownBlock {
  work.nodeVisits++;
  work.nodeCopies++;
  return {
    id: block.id,
    kind: block.kind,
    range: { start: block.range.start, end: block.range.end },
    closed: block.closed,
    fenceCharacter: block.fenceCharacter,
    fenceLength: block.fenceLength
  };
}
