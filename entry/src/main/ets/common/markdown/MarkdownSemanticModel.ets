/**
 * 语义树只描述当前原文，不承载样式、展开、滚动或异步资源。
 * range 包含标记符；容器与子节点允许包含，顶层节点连续覆盖原文。
 * parts 将消解容器前缀后的文本映回原文；text 只用于解码后的叶子/代码内容。
 */
import { MarkdownDocumentToken, MarkdownEndReason, MarkdownSourceRange } from './MarkdownDocumentModel';
import { foldMarkdownLabel } from './MarkdownCaseFold';

export type MarkdownNodeKind = 'blank' | 'paragraph' | 'heading' | 'thematicBreak' | 'blockquote' |
  'list' | 'listItem' | 'codeBlock' | 'table' | 'tableRow' | 'tableCell' | 'mathBlock' |
  'referenceDefinition' | 'footnoteDefinition' | 'toc' | 'htmlBlock' | 'text' | 'emphasis' |
  'strong' | 'strikethrough' | 'highlight' | 'code' | 'softBreak' | 'hardBreak' | 'link' | 'image' |
  'math' | 'subscript' | 'superscript' | 'footnoteReference' | 'htmlInline';

export interface MarkdownTextSlice {
  text: string;
  start: number;
}

export interface MarkdownNode {
  id: number;
  kind: MarkdownNodeKind;
  range: MarkdownSourceRange;
  children: MarkdownNode[];
  parts: MarkdownTextSlice[];
  text: string;
  destination: string;
  title: string;
  label: string;
  closed: boolean;
  level: number;
  ordered: boolean;
  startNumber: number;
  tight: boolean;
  checked: boolean | undefined;
  language: string;
  alignments: string[];
  headingId: string;
}

export interface MarkdownReference {
  label: string;
  destination: string;
  title: string;
}

export interface MarkdownInlineContext {
  references: Map<string, MarkdownReference>;
  footnotes: Map<string, number>;
  work: MarkdownSemanticWork;
}

/** 累计工作量而非 CPU 指令数。语义读取按需执行，不藏进 append 的源缓冲路径。 */
export class MarkdownSemanticWork {
  parsedUnits: number = 0;
  inlineUnits: number = 0;
  reparsedUnits: number = 0;
  materializedUnits: number = 0;
  nodeVisits: number = 0;
  nodeCopies: number = 0;
  fullParses: number = 0;
  suffixParses: number = 0;
  dependencyInvalidations: number = 0;
  retainedNodes: number = 0;
  retainedDefinitions: number = 0;
  retainedOutlineEntries: number = 0;
  retainedIdentities: number = 0;
}

export interface MarkdownHeadingEntry {
  nodeId: number;
  headingId: string;
  level: number;
  text: string;
}

export interface MarkdownSemanticSnapshot {
  token: MarkdownDocumentToken;
  nodes: MarkdownNode[];
  outline: MarkdownHeadingEntry[];
  sourceLength: number;
  endReason: MarkdownEndReason | undefined;
}

export function markdownNode(kind: MarkdownNodeKind, start: number, end: number): MarkdownNode {
  return {
    id: 0, kind: kind, range: { start: start, end: end }, children: [], parts: [], text: '',
    destination: '', title: '', label: '', closed: true, level: 0, ordered: false,
    startNumber: 1, tight: true, checked: undefined, language: '', alignments: [], headingId: ''
  };
}

export function normalizeMarkdownLabel(label: string): string {
  return foldMarkdownLabel(label.trim().replace(/\s+/g, ' '));
}

/** 快照拷贝 memo 载体（表格键 B2）：prev = 上一拍「源节点 → 快照拷贝」表，next = 本拍
 *  重建表（snapshot 结束时整表替换 prev，死对象随表脱落）。 */
export interface MarkdownCopyMemo {
  prev: Map<MarkdownNode, MarkdownNode>;
  next: Map<MarkdownNode, MarkdownNode>;
}

export function copyMarkdownNode(node: MarkdownNode, work: MarkdownSemanticWork,
  memo?: MarkdownCopyMemo): MarkdownNode {
  // memo 命中（源对象与上一拍同对象 ⇒ 同值 ⇒ 上拍拷贝仍有效）直接复用，不深拷贝不递归。
  // 清表义务在文档侧两处：定义失效帧与 clear()——漏清 = 命中陈值 = 静默错渲染。
  if (memo !== undefined) {
    const cached: MarkdownNode | undefined = memo.prev.get(node);
    if (cached !== undefined) {
      memo.next.set(node, cached);
      return cached;
    }
  }
  work.nodeVisits++;
  work.nodeCopies++;
  const result: MarkdownNode = markdownNode(node.kind, node.range.start, node.range.end);
  result.id = node.id;
  result.text = node.text;
  result.destination = node.destination;
  result.title = node.title;
  result.label = node.label;
  result.closed = node.closed;
  result.level = node.level;
  result.ordered = node.ordered;
  result.startNumber = node.startNumber;
  result.tight = node.tight;
  result.checked = node.checked;
  result.language = node.language;
  result.headingId = node.headingId;
  result.alignments = node.alignments.slice();
  for (let index: number = 0; index < node.parts.length; index++) {
    result.parts.push({ text: node.parts[index].text, start: node.parts[index].start });
  }
  for (let index: number = 0; index < node.children.length; index++) {
    result.children.push(copyMarkdownNode(node.children[index], work, memo));
  }
  if (memo !== undefined) memo.next.set(node, result);
  return result;
}
