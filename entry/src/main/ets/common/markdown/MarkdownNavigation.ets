/** 文档内锚点索引，只持当前树的标量；点击才解析目标，不改变消息滚动策略。 */
import { MarkdownDocumentToken } from './MarkdownDocumentModel';
import { MarkdownNode, normalizeMarkdownLabel } from './MarkdownSemanticModel';

export interface MarkdownAnchorEntry {
  destination: string;
  nodeId: number;
  number: number;
  footnote?: string;
}

export interface MarkdownReferenceJump {
  referenceId: number;
  serial: number;
}

export function markdownAnchorId(token: MarkdownDocumentToken, nodeId: number): string {
  return 'markdown/' + token.documentId.length.toString() + ':' + token.documentId + '/' +
    token.generation.toString() + '/' + nodeId.toString();
}

export function markdownFootnoteDestination(label: string): string {
  return 'footnote:' + normalizeMarkdownLabel(label);
}

export function markdownAnchorEntries(nodes: MarkdownNode[]): MarkdownAnchorEntry[] {
  const entries: MarkdownAnchorEntry[] = [];
  const labels: Set<string> = new Set<string>();
  collectAnchors(nodes, entries, labels);
  collectBacklinks(nodes, 0, entries, new Set<string>());
  return entries;
}

function collectAnchors(nodes: MarkdownNode[], entries: MarkdownAnchorEntry[], labels: Set<string>): void {
  for (const node of nodes) {
    if (node.kind === 'heading') {
      entries.push({ destination: '#' + node.headingId, nodeId: node.id, number: 0 });
    } else if (node.kind === 'footnoteDefinition') {
      const destination: string = markdownFootnoteDestination(node.label);
      if (!labels.has(destination)) {
        labels.add(destination);
        entries.push({ destination: destination, nodeId: node.id, number: labels.size });
      }
    }
    collectAnchors(node.children, entries, labels);
  }
}

function collectBacklinks(nodes: MarkdownNode[], owner: number, entries: MarkdownAnchorEntry[],
  seen: Set<string>): void {
  for (const node of nodes) {
    const block: number = ['paragraph', 'heading', 'tableCell', 'footnoteDefinition'].indexOf(node.kind) >= 0 ?
      node.id : owner;
    if (node.kind === 'footnoteReference' && block > 0) {
      entries.push({ destination: 'reference:' + node.id.toString(), nodeId: block, number: node.id,
        footnote: markdownFootnoteDestination(node.label) });
      const destination: string = 'back:' + markdownFootnoteDestination(node.label);
      if (!seen.has(destination)) {
        seen.add(destination);
        entries.push({ destination: destination, nodeId: block, number: 0 });
      }
    }
    collectBacklinks(node.children, block, entries, seen);
  }
}

export function markdownAnchorTarget(entries: MarkdownAnchorEntry[], destination: string): number {
  if (destination.startsWith('node:')) {
    const nodeId: number = Number(destination.substring(5));
    return Number.isSafeInteger(nodeId) && nodeId > 0 ? nodeId : 0;
  }
  const exact: MarkdownAnchorEntry | undefined = entries.find((entry: MarkdownAnchorEntry): boolean =>
    entry.destination === destination);
  if (exact !== undefined) { return exact.nodeId; }
  let decoded: string = destination;
  if (destination.startsWith('#')) {
    try { decoded = '#' + decodeURIComponent(destination.substring(1)); } catch (error) { return 0; }
  }
  const target: MarkdownAnchorEntry | undefined = entries.find((entry: MarkdownAnchorEntry): boolean =>
    entry.destination === decoded);
  return target === undefined ? 0 : target.nodeId;
}

export function markdownFootnoteNumber(entries: MarkdownAnchorEntry[], label: string): number {
  const destination: string = markdownFootnoteDestination(label);
  const target: MarkdownAnchorEntry | undefined = entries.find((entry: MarkdownAnchorEntry): boolean =>
    entry.destination === destination);
  return target === undefined ? 0 : target.number;
}

export function markdownHasNode(nodes: MarkdownNode[], id: number): boolean {
  for (const node of nodes) {
    if (node.id === id || markdownHasNode(node.children, id)) { return true; }
  }
  return false;
}
